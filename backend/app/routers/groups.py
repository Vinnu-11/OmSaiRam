# Om Sai Ram
# Groups router — CRUD for reading groups and membership management.

import random
import string

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember
from ..schemas import (
    CreateGroupRequest,
    UpdateGroupRequest,
    SetMemberRoleRequest,
    JoinGroupRequest,
    GroupResponse,
    GroupDetailResponse,
    GroupMemberResponse,
    GroupsListResponse,
)
from ..middleware.auth import get_current_user

router = APIRouter()


def _generate_invite_code() -> str:
    """Generate a random 6-character alphanumeric invite code."""
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _group_to_response(group: Group) -> GroupResponse:
    """Convert a Group model to a GroupResponse with member count."""
    return GroupResponse(
        id=group.id,
        name=group.name,
        description=group.description,
        mode=group.mode,
        invite_code=group.invite_code,
        created_by=group.created_by,
        member_count=len(group.members),
        chapters_per_week=group.chapters_per_week or 2,
        start_chapter=group.start_chapter or 1,
        current_week=group.current_week or 1,
        created_at=group.created_at,
    )


@router.get("", response_model=GroupsListResponse)
def list_groups(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List all groups the current user belongs to."""
    memberships = (
        db.query(GroupMember)
        .filter(GroupMember.user_id == current_user.id)
        .all()
    )
    group_ids = [m.group_id for m in memberships]
    groups = db.query(Group).filter(Group.id.in_(group_ids)).all() if group_ids else []

    return GroupsListResponse(
        groups=[_group_to_response(g) for g in groups]
    )


@router.post("", response_model=GroupResponse, status_code=status.HTTP_201_CREATED)
def create_group(
    request: CreateGroupRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a new reading group.

    The creating user is automatically added as an admin member.
    A unique invite code is generated for the group.
    """
    # Generate a unique invite code
    invite_code = _generate_invite_code()
    while db.query(Group).filter(Group.invite_code == invite_code).first():
        invite_code = _generate_invite_code()

    # Create the group
    group = Group(
        name=request.name,
        description=request.description,
        mode=request.mode,
        invite_code=invite_code,
        created_by=current_user.id,
        chapters_per_week=request.chapters_per_week,
        start_chapter=request.start_chapter,
    )
    db.add(group)
    db.flush()  # Get the group ID before adding member

    # Add creator as admin member
    member = GroupMember(
        group_id=group.id,
        user_id=current_user.id,
        role="admin",
    )
    db.add(member)
    db.commit()
    db.refresh(group)

    return _group_to_response(group)


@router.post("/join", response_model=GroupResponse)
def join_group(
    request: JoinGroupRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Join a group using an invite code.

    Raises 404 if the invite code is invalid.
    Raises 400 if already a member.
    """
    group = db.query(Group).filter(Group.invite_code == request.invite_code).first()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid invite code",
        )

    # Check if already a member
    existing = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group.id,
            GroupMember.user_id == current_user.id,
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You are already a member of this group",
        )

    # Add as member
    member = GroupMember(
        group_id=group.id,
        user_id=current_user.id,
        role="member",
    )
    db.add(member)
    db.commit()
    db.refresh(group)

    return _group_to_response(group)


@router.get("/{group_id}", response_model=GroupDetailResponse)
def get_group_detail(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get full details of a group including members.

    Only accessible to group members.
    """
    # Verify the user is a member
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

    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Group not found",
        )

    # Get members with user info
    members_data = []
    for member in group.members:
        user = db.query(User).filter(User.id == member.user_id).first()
        if user:
            members_data.append(
                GroupMemberResponse(
                    id=member.id,
                    user_id=member.user_id,
                    name=user.name,
                    avatar_url=user.avatar_url,
                    role=member.role,
                    joined_at=member.joined_at,
                )
            )

    return GroupDetailResponse(
        group=_group_to_response(group),
        members=members_data,
    )


@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a group. Only the group admin can do this."""
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role == "admin",
        )
        .first()
    )
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the group admin can delete the group",
        )

    group = db.query(Group).filter(Group.id == group_id).first()
    if group:
        db.delete(group)
        db.commit()


@router.delete("/{group_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Leave a group. Admins cannot leave — they must delete the group instead."""
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
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You are not a member of this group",
        )

    if membership.role == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admins cannot leave. Transfer ownership or delete the group.",
        )

    db.delete(membership)
    db.commit()


@router.patch("/{group_id}/settings", response_model=GroupResponse)
def update_group_settings(
    group_id: str,
    request: UpdateGroupRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update group schedule settings. Only admins can do this."""
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role == "admin",
        )
        .first()
    )
    if not membership:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can update group settings")

    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    if request.chapters_per_week is not None:
        group.chapters_per_week = request.chapters_per_week
    if request.start_chapter is not None:
        group.start_chapter = request.start_chapter
    if request.current_week is not None:
        group.current_week = request.current_week

    db.commit()
    db.refresh(group)
    return _group_to_response(group)


@router.patch("/{group_id}/members/role", response_model=GroupMemberResponse)
def set_member_role(
    group_id: str,
    request: SetMemberRoleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Assign or change a member's role. Only the group admin can do this."""
    admin_membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role == "admin",
        )
        .first()
    )
    if not admin_membership:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the admin can change member roles")

    target = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == request.user_id)
        .first()
    )
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Member not found")

    # Admin cannot demote themselves
    if target.user_id == current_user.id and request.role != "admin":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Admin cannot change their own role")

    target.role = request.role
    db.commit()
    db.refresh(target)

    user = db.query(User).filter(User.id == target.user_id).first()
    return GroupMemberResponse(
        id=target.id,
        user_id=target.user_id,
        name=user.name if user else "Unknown",
        avatar_url=user.avatar_url if user else None,
        role=target.role,
        joined_at=target.joined_at,
    )
