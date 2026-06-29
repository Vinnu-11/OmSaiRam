# Om Sai Ram
# Assignments router — manage chapter assignments within groups.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember, Chapter, ReadingAssignment, ReadingProgress
from ..schemas import CreateAssignmentRequest, AssignmentResponse
from ..middleware.auth import get_current_user

router = APIRouter()


@router.post("", response_model=AssignmentResponse, status_code=status.HTTP_201_CREATED)
def create_assignment(
    request: CreateAssignmentRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Assign a chapter to a user in a group.

    Only group admins can create assignments.
    Prevents duplicate assignments of the same chapter to the same user in a group.
    """
    # Verify current user is group admin
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == request.group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role == "admin",
        )
        .first()
    )
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only group admins can create assignments",
        )

    # Verify target user is a member
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

    # Verify chapter exists
    chapter = db.query(Chapter).filter(Chapter.id == request.chapter_id).first()
    if not chapter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chapter not found",
        )

    # Check for duplicate assignment
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

    # Create the assignment
    assignment = ReadingAssignment(
        group_id=request.group_id,
        user_id=request.user_id,
        chapter_id=request.chapter_id,
    )
    db.add(assignment)
    db.flush()

    # Create initial progress record
    progress = ReadingProgress(
        assignment_id=assignment.id,
        status="not_started",
    )
    db.add(progress)
    db.commit()
    db.refresh(assignment)

    return AssignmentResponse(
        id=assignment.id,
        group_id=assignment.group_id,
        user_id=assignment.user_id,
        chapter_id=assignment.chapter_id,
        chapter_title=chapter.title,
        status="not_started",
        assigned_at=assignment.assigned_at,
    )


@router.get("/group/{group_id}", response_model=list[AssignmentResponse])
def get_group_assignments(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all assignments for a group.

    Only accessible to group members.
    """
    # Verify membership
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
        )
        .first()
    )
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    assignments = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.group_id == group_id)
        .all()
    )

    result = []
    for assignment in assignments:
        chapter = db.query(Chapter).filter(Chapter.id == assignment.chapter_id).first()
        progress = assignment.progress
        result.append(
            AssignmentResponse(
                id=assignment.id,
                group_id=assignment.group_id,
                user_id=assignment.user_id,
                chapter_id=assignment.chapter_id,
                chapter_title=chapter.title if chapter else None,
                status=progress.status if progress else "not_started",
                assigned_at=assignment.assigned_at,
            )
        )

    return result


@router.get("/my", response_model=list[AssignmentResponse])
def get_my_assignments(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all assignments for the current user across all groups."""
    assignments = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.user_id == current_user.id)
        .all()
    )

    result = []
    for assignment in assignments:
        chapter = db.query(Chapter).filter(Chapter.id == assignment.chapter_id).first()
        progress = assignment.progress
        result.append(
            AssignmentResponse(
                id=assignment.id,
                group_id=assignment.group_id,
                user_id=assignment.user_id,
                chapter_id=assignment.chapter_id,
                chapter_title=chapter.title if chapter else None,
                status=progress.status if progress else "not_started",
                assigned_at=assignment.assigned_at,
            )
        )

    return result


@router.delete("/{assignment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_assignment(
    assignment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete an assignment. Only group admins can do this."""
    assignment = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.id == assignment_id)
        .first()
    )
    if not assignment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Assignment not found",
        )

    # Verify admin
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == assignment.group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role == "admin",
        )
        .first()
    )
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only group admins can delete assignments",
        )

    db.delete(assignment)
    db.commit()
