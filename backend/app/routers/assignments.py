# Om Sai Ram
# Assignments router — manage chapter assignments within groups.

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember, Chapter, ReadingAssignment, ReadingProgress
from ..schemas import CreateAssignmentRequest, AutoScheduleRequest, AssignmentResponse
from ..middleware.auth import get_current_user

router = APIRouter()


def _can_assign(role: str) -> bool:
    return role in ("admin", "group_lead")


def _monday_of_week(reference: datetime, weeks_ahead: int) -> datetime:
    """Return the Monday date for `weeks_ahead` weeks from the reference Monday."""
    days_to_monday = reference.weekday()  # 0=Monday
    this_monday = reference - timedelta(days=days_to_monday)
    return (this_monday + timedelta(weeks=weeks_ahead)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def _build_assignment_response(assignment: ReadingAssignment, db: Session) -> AssignmentResponse:
    chapter = db.query(Chapter).filter(Chapter.id == assignment.chapter_id).first()
    user = db.query(User).filter(User.id == assignment.user_id).first()
    progress = assignment.progress
    return AssignmentResponse(
        id=assignment.id,
        group_id=assignment.group_id,
        user_id=assignment.user_id,
        user_name=user.name if user else None,
        chapter_id=assignment.chapter_id,
        chapter_number=chapter.number if chapter else None,
        chapter_title=chapter.title if chapter else None,
        week_number=assignment.week_number,
        scheduled_date=assignment.scheduled_date,
        status=progress.status if progress else "not_started",
        assigned_at=assignment.assigned_at,
    )


@router.post("", response_model=AssignmentResponse, status_code=status.HTTP_201_CREATED)
def create_assignment(
    request: CreateAssignmentRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Assign a chapter to a user in a group.

    Only admins and group leads can create assignments.
    Prevents duplicate assignments of the same chapter to the same user in a group.
    """
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == request.group_id,
            GroupMember.user_id == current_user.id,
        )
        .first()
    )
    if not membership or not _can_assign(membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins and group leads can create assignments",
        )

    target_membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == request.group_id,
            GroupMember.user_id == request.user_id,
        )
        .first()
    )
    if not target_membership:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Target user is not a member of this group",
        )

    chapter = db.query(Chapter).filter(Chapter.id == request.chapter_id).first()
    if not chapter:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chapter not found")

    existing = (
        db.query(ReadingAssignment)
        .filter(
            ReadingAssignment.group_id == request.group_id,
            ReadingAssignment.user_id == request.user_id,
            ReadingAssignment.chapter_id == request.chapter_id,
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This chapter is already assigned to this user in this group",
        )

    assignment = ReadingAssignment(
        group_id=request.group_id,
        user_id=request.user_id,
        chapter_id=request.chapter_id,
        week_number=request.week_number,
        scheduled_date=request.scheduled_date,
    )
    db.add(assignment)
    db.flush()

    progress = ReadingProgress(assignment_id=assignment.id, status="not_started")
    db.add(progress)
    db.commit()
    db.refresh(assignment)

    return _build_assignment_response(assignment, db)


@router.post("/auto-schedule", response_model=list[AssignmentResponse], status_code=status.HTTP_201_CREATED)
def auto_schedule(
    request: AutoScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Auto-schedule upcoming chapters for all group members week-by-week.

    Distributes chapters evenly across members for each week.
    Admins and group leads can trigger this.
    """
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == request.group_id,
            GroupMember.user_id == current_user.id,
        )
        .first()
    )
    if not membership or not _can_assign(membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins and group leads can schedule assignments",
        )

    group = db.query(Group).filter(Group.id == request.group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    members = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == request.group_id)
        .all()
    )
    if not members:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Group has no members")

    chapters_per_week = group.chapters_per_week or 2
    now = datetime.utcnow()
    created = []

    for week_offset in range(request.weeks_ahead):
        week_number = group.current_week + week_offset
        monday = _monday_of_week(now, week_offset)

        # Chapters assigned this week (round-robin across members)
        for i in range(chapters_per_week):
            chapter_number = request.start_chapter + week_offset * chapters_per_week + i
            # chapters are numbered 1-based; look up by number
            chapter = db.query(Chapter).filter(Chapter.number == chapter_number).first()
            if not chapter:
                continue  # Skip if no chapter with that number exists

            member = members[i % len(members)]

            existing = (
                db.query(ReadingAssignment)
                .filter(
                    ReadingAssignment.group_id == request.group_id,
                    ReadingAssignment.chapter_id == chapter.id,
                    ReadingAssignment.week_number == week_number,
                )
                .first()
            )
            if existing:
                continue

            assignment = ReadingAssignment(
                group_id=request.group_id,
                user_id=member.user_id,
                chapter_id=chapter.id,
                week_number=week_number,
                scheduled_date=monday,
            )
            db.add(assignment)
            db.flush()

            progress = ReadingProgress(assignment_id=assignment.id, status="not_started")
            db.add(progress)
            db.flush()
            created.append(assignment)

    db.commit()
    for a in created:
        db.refresh(a)

    return [_build_assignment_response(a, db) for a in created]


@router.post("/advance-week/{group_id}", response_model=dict)
def advance_week(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Advance the group to the next reading week.

    Only admins and group leads can do this.
    """
    membership = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == current_user.id)
        .first()
    )
    if not membership or not _can_assign(membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins and group leads can advance the week",
        )

    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    group.current_week = (group.current_week or 1) + 1
    db.commit()

    return {"current_week": group.current_week}


@router.get("/group/{group_id}", response_model=list[AssignmentResponse])
def get_group_assignments(
    group_id: str,
    week_number: int = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all assignments for a group, optionally filtered by week."""
    membership = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == current_user.id)
        .first()
    )
    if not membership:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a member of this group")

    query = db.query(ReadingAssignment).filter(ReadingAssignment.group_id == group_id)
    if week_number is not None:
        query = query.filter(ReadingAssignment.week_number == week_number)

    assignments = query.order_by(ReadingAssignment.week_number, ReadingAssignment.assigned_at).all()
    return [_build_assignment_response(a, db) for a in assignments]


@router.get("/my", response_model=list[AssignmentResponse])
def get_my_assignments(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all assignments for the current user across all groups."""
    assignments = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.user_id == current_user.id)
        .order_by(ReadingAssignment.scheduled_date)
        .all()
    )
    return [_build_assignment_response(a, db) for a in assignments]


@router.delete("/{assignment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_assignment(
    assignment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete an assignment. Admins and group leads can do this."""
    assignment = db.query(ReadingAssignment).filter(ReadingAssignment.id == assignment_id).first()
    if not assignment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Assignment not found")

    membership = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == assignment.group_id, GroupMember.user_id == current_user.id)
        .first()
    )
    if not membership or not _can_assign(membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins and group leads can delete assignments",
        )

    db.delete(assignment)
    db.commit()
