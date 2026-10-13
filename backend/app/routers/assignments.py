# Om Sai Ram
# Assignments router — manage chapter assignments within groups.

from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember, Chapter, ReadingAssignment, ReadingProgress
from ..schemas import (
    CreateAssignmentRequest,
    AutoScheduleRequest,
    AssignmentResponse,
    SuggestScheduleRequest,
    SuggestScheduleResponse,
    SuggestedSlot,
)
from ..middleware.auth import get_current_user
from ..services.chapter_units import (
    TOTAL_CHAPTERS, chapter_start, chapter_end, chapter_label,
    reading_units, unit_position, unit_number,
)

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
        chapter_label=chapter_label(chapter.number) if chapter else None,
        chapter_end_number=chapter_end(chapter.number) if chapter else None,
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
    Prevents duplicate reading units for the same member and week.
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

    start, end = chapter_start(chapter.number), chapter_end(chapter.number)
    canonical = db.query(Chapter).filter(
        Chapter.number == start, Chapter.language == chapter.language,
    ).first()
    if not canonical:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chapter not found")
    chapter = canonical

    existing = (
        db.query(ReadingAssignment)
        .join(Chapter)
        .filter(
            ReadingAssignment.group_id == request.group_id,
            ReadingAssignment.user_id == request.user_id,
            ReadingAssignment.week_number == request.week_number,
            Chapter.number.between(start, end),
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This chapter is already assigned to this user for this week",
        )

    scheduled_date = request.scheduled_date
    if scheduled_date is None:
        group = db.query(Group).filter(Group.id == request.group_id).first()
        if not group:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")
        scheduled_date = _monday_of_week(
            datetime.utcnow(), request.week_number - (group.current_week or 1),
        )

    assignment = ReadingAssignment(
        group_id=request.group_id,
        user_id=request.user_id,
        chapter_id=chapter.id,
        week_number=request.week_number,
        scheduled_date=scheduled_date,
    )
    db.add(assignment)
    db.flush()

    progress = ReadingProgress(assignment_id=assignment.id, status="not_started")
    db.add(progress)
    db.commit()
    db.refresh(assignment)

    return _build_assignment_response(assignment, db)


# ─── Schedule mode helpers ───────────────────────────────────────────────────

def _member_chapter_start(
    mode: str,
    week_offset: int,
    member_index: int,
    start_chapter: int,
    chapters_per_week: int,
    member_count: int,
) -> int:
    """Return the first chapter number for a given member in a given week.

    week_offset is 0-based (0 = first scheduled week).
    member_index is 0-based in join order.
    """
    W = chapters_per_week
    K = week_offset  # 0-based
    i = member_index  # 0-based
    s = start_chapter

    if mode == "independent":
        # No overlap between weeks.  Total N*W chapters consumed each week.
        return s + K * member_count * W + i * W
    elif mode == "rotating_window":
        # Window slides by W each week.  Intra-week gap between members = W.
        # Formula: s + (K + i) * W
        return s + (K + i) * W
    elif mode == "dense_window":
        # Window slides by W each week.  Intra-week gap between members = 1.
        # Formula: s + K * W + i
        return s + K * W + i
    elif mode == "synchronized":
        # All members read the same chapters every week.
        return s + K * W
    else:
        return s + K * member_count * W + i * W  # fallback = independent


def _apply_remainder(
    chapter_number: int,
    remainder_mode: str,
    total_chapters: int,
    last_valid_chapter: int,
) -> int | None:
    """Adjust a chapter number that exceeds the book length, or return None to skip."""
    if chapter_number <= total_chapters:
        return chapter_number
    if remainder_mode == "cycle":
        return ((chapter_number - 1) % total_chapters) + 1
    # truncate / manual / extend_last / round_robin → caller handles the extra
    return None


@router.post("/auto-schedule", status_code=status.HTTP_201_CREATED)
def auto_schedule(
    request: AutoScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Auto-schedule upcoming chapters for all group members week-by-week.

    schedule_mode controls the intra-week and inter-week chapter distribution:
      independent    — unique non-overlapping slices (default / existing behaviour)
      rotating_window — window slides W chapters per week; adjacent members share
                       consecutive slices
      dense_window   — window slides W chapters per week; members spaced 1 chapter
                       apart, maximising overlap for discussion chains
      synchronized   — all members read the same chapters each week

    remainder_mode controls what happens when chapters run past the book end:
      manual         — flag for group lead to assign manually (default)
      truncate       — member gets fewer chapters; remainder reported
      extend_last    — last member absorbs the extra chapter(s)
      round_robin    — extras looped back to members 0, 1, 2 …
      cycle          — chapter wraps around to Ch.1 after the last chapter
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
        .order_by(GroupMember.joined_at)
        .all()
    )
    if not members:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Group has no members")

    # Schedule reading units, not individual numbers inside a combined range.
    total_chapters = db.query(func.max(Chapter.number)).scalar() or TOTAL_CHAPTERS
    units = reading_units(total_chapters)
    start_position = unit_position(request.start_chapter, units, total_chapters)

    chapters_per_week = group.chapters_per_week or 2
    member_count = len(members)
    mode = request.schedule_mode
    remainder_mode = request.remainder_mode
    now = datetime.utcnow()
    created: list = []
    remainder_chapters: list[dict] = []

    for week_offset in range(request.weeks_ahead):
        week_number = group.current_week + week_offset
        monday = _monday_of_week(now, week_offset)
        last_member_idx = member_count - 1

        # For extend_last: track if we already extended this week
        extended_this_week = False

        for member_index, member in enumerate(members):
            member_start = _member_chapter_start(
                mode, week_offset, member_index,
                start_position, chapters_per_week, member_count,
            )

            # Determine how many chapters this member reads this slot.
            # Default = chapters_per_week.  extend_last adds one extra to the
            # last member if the previous slot ended short.
            slots = chapters_per_week

            for slot in range(slots):
                position = member_start + slot
                chapter_number = unit_number(position, units, total_chapters)
                resolved_position = _apply_remainder(position, remainder_mode, len(units), len(units))
                resolved = units[resolved_position - 1] if resolved_position is not None else None

                if resolved is None:
                    # Chapter is past end of book and mode is not cycle
                    if remainder_mode == "extend_last" and member_index == last_member_idx and not extended_this_week:
                        # Already handled by naturalntruncation; nothing to extend
                        pass
                    elif remainder_mode in ("manual", "truncate", "extend_last", "round_robin"):
                        remainder_chapters.append({
                            "week_number": week_number,
                            "chapter_number": chapter_number,
                            "user_id": member.user_id,
                        })
                    continue

                # round_robin: give extras back to early members
                if remainder_mode == "round_robin" and chapter_number > total_chapters:
                    resolved = units[(position - 1) % len(units)]

                chapter = db.query(Chapter).filter(Chapter.number == resolved).first()
                if not chapter:
                    remainder_chapters.append({
                        "week_number": week_number,
                        "chapter_number": resolved,
                        "user_id": member.user_id,
                    })
                    continue

                # Skip if already assigned to anyone in this group for this week
                existing = (
                    db.query(ReadingAssignment)
                    .join(Chapter)
                    .filter(
                        ReadingAssignment.group_id == request.group_id,
                        ReadingAssignment.user_id == member.user_id,
                        Chapter.number.between(resolved, chapter_end(resolved)),
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

    return {
        "assignments": [_build_assignment_response(a, db) for a in created],
        "remainder_chapters": remainder_chapters,
    }


# ─── Smart Suggest Endpoint ───────────────────────────────────────────────────

@router.post("/suggest", response_model=SuggestScheduleResponse)
def suggest_schedule(
    request: SuggestScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Detect the group lead's chapter-assignment pattern from 2+ manual hints
    and return a full suggested grid for all members × requested weeks ahead.

    No assignments are written to the database — the lead reviews the preview
    and can then call /auto-schedule with the detected mode to confirm.

    Pattern detection (from hints sorted by position):
      step = hints[1].chapter_start − hints[0].chapter_start
      W    = group.chapters_per_week

      step == W  → "non_overlapping" (independent / rotating-window style)
      step == 1  → "dense"
      other      → "custom" (arbitrary step; extrapolated linearly)

    For following weeks every member advances W chapters from their position
    in the first hint week, matching both rotating_window and dense_window
    inter-week behaviour.
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
            detail="Only group leads and admins can use smart suggestions",
        )

    group = db.query(Group).filter(Group.id == request.group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    members = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == request.group_id)
        .order_by(GroupMember.joined_at)
        .all()
    )
    member_count = len(members)
    if member_count == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Group has no members")

    W = group.chapters_per_week or 2
    total_chapters = db.query(func.max(Chapter.number)).scalar() or TOTAL_CHAPTERS
    units = reading_units(total_chapters)

    # ── Detect pattern ──────────────────────────────────────────────────────
    hints_sorted = sorted(request.hints, key=lambda h: h.position)

    if len(hints_sorted) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Provide at least 2 hints (positions 0 and 1) to detect a pattern",
        )

    step = (
        unit_position(hints_sorted[1].chapter_start, units, total_chapters)
        - unit_position(hints_sorted[0].chapter_start, units, total_chapters)
    )

    if step == W:
        detected_mode = "non_overlapping"
    elif step == 1:
        detected_mode = "dense"
    else:
        detected_mode = "custom"

    # Base chapter for position 0 in the hint week
    base_chapter = unit_position(hints_sorted[0].chapter_start, units, total_chapters)

    # Build a position → chapter_start lookup for manually-provided hints
    manual_positions = {
        h.position: unit_position(h.chapter_start, units, total_chapters)
        for h in hints_sorted
    }

    # ── Build suggestion grid ────────────────────────────────────────────────
    suggestions: list[SuggestedSlot] = []
    remainder_chapters: list[int] = []
    remainder_mode = request.remainder_mode

    # Week 0 = request.week_number, Week 1 = request.week_number + 1, …
    for week_idx in range(1 + request.weeks_ahead):
        week_number = request.week_number + week_idx
        week_advance = week_idx * W   # how much the window moves each week

        for pos, member in enumerate(members):
            # chapter_start for this member in this week
            if pos in manual_positions and week_idx == 0:
                ch_start = manual_positions[pos]
                is_manual = True
            else:
                ch_start = base_chapter + week_advance + pos * step
                is_manual = False

            # Build list of chapter numbers for this slot
            chapter_nums: list[int] = []
            for slot in range(W):
                position = ch_start + slot
                ch = unit_number(position, units, total_chapters)

                if position > len(units):
                    if remainder_mode == "cycle":
                        ch = units[(position - 1) % len(units)]
                    elif remainder_mode == "extend_last" and pos == member_count - 1:
                        # Allow extend — chapter included as-is (lead is aware)
                        pass
                    else:
                        remainder_chapters.append(ch)
                        continue   # skip this slot in the suggestion

                chapter_nums.append(ch)

            if not chapter_nums:
                continue

            # Resolve member user info
            user = db.query(User).filter(User.id == member.user_id).first()
            user_name = user.name if user else member.user_id

            suggestions.append(SuggestedSlot(
                week_number=week_number,
                position=pos,
                user_id=member.user_id,
                user_name=user_name,
                chapter_numbers=chapter_nums,
                chapter_labels=[chapter_label(n) for n in chapter_nums],
                is_manual=is_manual,
            ))

    return SuggestScheduleResponse(
        detected_mode=detected_mode,
        detected_step=step,
        chapters_per_member=W,
        suggestions=suggestions,
        remainder_chapters=sorted(set(remainder_chapters)),
    )


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
    week_number: Optional[int] = None,
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
