# Om Sai Ram
# Pydantic schemas for request/response validation.

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field


# ─── Auth Schemas ─────────────────────────────────────────────────────────────


class RegisterRequest(BaseModel):
    """Request body for user registration."""
    name: str = Field(..., min_length=1, max_length=255)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)


class LoginRequest(BaseModel):
    """Request body for email/password login."""
    email: EmailStr
    password: str


class SocialAuthRequest(BaseModel):
    """Request body for social login (Google/Apple)."""
    provider: str = Field(..., pattern="^(google|apple)$")
    id_token: str
    name: Optional[str] = None


class RefreshRequest(BaseModel):
    """Request body for token refresh."""
    refresh_token: str


class UserResponse(BaseModel):
    """Public user data returned in API responses."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    name: str
    avatar_url: Optional[str] = None
    auth_provider: str
    created_at: datetime


class AuthResponse(BaseModel):
    """Response containing user data and tokens."""
    user: UserResponse
    access_token: str
    refresh_token: str


# ─── Group Schemas ────────────────────────────────────────────────────────────


class CreateGroupRequest(BaseModel):
    """Request body for creating a new group."""
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = Field(None, max_length=1000)
    mode: str = Field(default="chapter_wise", pattern="^(chapter_wise|saptah)$")


class JoinGroupRequest(BaseModel):
    """Request body for joining a group via invite code."""
    invite_code: str = Field(..., min_length=4, max_length=8)


class GroupResponse(BaseModel):
    """Group data returned in API responses."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: Optional[str] = None
    mode: str
    invite_code: str
    created_by: str
    member_count: int = 0
    created_at: datetime


class GroupMemberResponse(BaseModel):
    """Group member data."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    avatar_url: Optional[str] = None
    role: str
    joined_at: datetime


class GroupDetailResponse(BaseModel):
    """Full group details including members."""
    group: GroupResponse
    members: list[GroupMemberResponse]


class GroupsListResponse(BaseModel):
    """List of groups."""
    groups: list[GroupResponse]


# ─── Assignment Schemas ───────────────────────────────────────────────────────


class CreateAssignmentRequest(BaseModel):
    """Request to assign a chapter to a user in a group."""
    group_id: str
    user_id: str
    chapter_id: int


class AssignmentResponse(BaseModel):
    """Assignment data."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    user_id: str
    chapter_id: int
    chapter_title: Optional[str] = None
    status: str = "not_started"
    assigned_at: datetime


# ─── Progress Schemas ─────────────────────────────────────────────────────────


class UpdateProgressRequest(BaseModel):
    """Request to update reading progress."""
    status: str = Field(..., pattern="^(not_started|in_progress|completed)$")


class ProgressResponse(BaseModel):
    """Reading progress data."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    assignment_id: str
    status: str
    updated_at: datetime


# ─── Content Schemas ──────────────────────────────────────────────────────────


class ChapterResponse(BaseModel):
    """Chapter data for the reader."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    number: int
    title: str
    content: str
    language: str
    version: int


class ContentVersionResponse(BaseModel):
    """Current content version info."""
    language: str
    version: int
    total_chapters: int
