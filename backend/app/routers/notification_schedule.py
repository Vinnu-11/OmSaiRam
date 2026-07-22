# Om Sai Ram
# Notification schedule router — group leads set reading reminders for members.
#
# The schedule is stored per-group and fetched by each member's device so the
# Flutter app can schedule local notifications with escalating urgency as the
# weekly reading deadline approaches.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember, GroupNotificationSchedule
from ..schemas import SetNotificationScheduleRequest, NotificationScheduleResponse
from ..middleware.auth import get_current_user

router = APIRouter()


def _is_lead(role: str) -> bool:
    return role in ("admin", "group_lead")


def _get_membership(db: Session, group_id: str, user_id: str) -> GroupMember | None:
    return (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == user_id)
        .first()
    )


@router.put(
    "/{group_id}/notification-schedule",
    response_model=NotificationScheduleResponse,
    summary="Set notification schedule for a group",
)
def set_notification_schedule(
    group_id: str,
    request: SetNotificationScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create or update the weekly reading notification schedule for a group.

    Only group admins/leads can configure this.  Members call GET to fetch it
    so their devices can schedule local notifications.

    The schedule controls:
    - When the initial 'start reading' notification fires each week
      (expressed as days + hour from the Monday of the assignment week).
    - When the reading deadline falls (same offset format).
    - Whether escalating reminders are sent as the deadline closes in.
    """
    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    membership = _get_membership(db, group_id, current_user.id)
    if not membership or not _is_lead(membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only group admins and leads can set the notification schedule",
        )

    schedule = (
        db.query(GroupNotificationSchedule)
        .filter(GroupNotificationSchedule.group_id == group_id)
        .first()
    )

    if schedule is None:
        schedule = GroupNotificationSchedule(
            group_id=group_id,
            created_by=current_user.id,
        )
        db.add(schedule)

    schedule.initial_reminder_day_offset = request.initial_reminder_day_offset
    schedule.initial_reminder_hour = request.initial_reminder_hour
    schedule.initial_reminder_minute = request.initial_reminder_minute
    schedule.deadline_day_offset = request.deadline_day_offset
    schedule.deadline_hour = request.deadline_hour
    schedule.deadline_minute = request.deadline_minute
    schedule.escalation_enabled = request.escalation_enabled
    schedule.created_by = current_user.id

    db.commit()
    db.refresh(schedule)
    return schedule


@router.get(
    "/{group_id}/notification-schedule",
    response_model=NotificationScheduleResponse,
    summary="Fetch a group's notification schedule",
)
def get_notification_schedule(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return the notification schedule for a group.

    Any member can call this so the client can schedule local notifications.
    Returns 404 if the group lead hasn't configured a schedule yet.
    """
    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    membership = _get_membership(db, group_id, current_user.id)
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    schedule = (
        db.query(GroupNotificationSchedule)
        .filter(GroupNotificationSchedule.group_id == group_id)
        .first()
    )
    if not schedule:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No notification schedule has been set for this group yet",
        )

    return schedule
