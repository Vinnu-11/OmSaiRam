# Om Sai Ram
# Pydantic schemas for request/response validation.

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
import re


# ─── Auth Schemas ─────────────────────────────────────────────────────────────


class RegisterRequest(BaseModel):
    """Request body for user registration."""
    name: str = Field(..., min_length=1, max_length=255)
    email: Optional[EmailStr] = None
    phone_number: Optional[str] = Field(None, max_length=20)
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        digits = re.sub(r"[\s\-()]", "", v)
        if not re.match(r"^\+?[1-9]\d{7,14}$", digits):
            raise ValueError("Invalid phone number")
        return digits


class LoginRequest(BaseModel):
    """Request body for email/password login."""
    email: EmailStr
    password: str


class PhoneSendOtpRequest(BaseModel):
    """Request to send an OTP to a phone number."""
    phone_number: str = Field(..., min_length=7, max_length=20)

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        digits = re.sub(r"[\s\-()]", "", v)
        if not re.match(r"^\+?[1-9]\d{7,14}$", digits):
            raise ValueError("Invalid phone number — include country code, e.g. +91 9876543210")
        return digits


class PhoneVerifyOtpRequest(BaseModel):
    """Request to verify an OTP and log in or register."""
    phone_number: str
    otp: str = Field(..., min_length=4, max_length=8)
    # Provided only when creating a new account via phone
    name: Optional[str] = Field(None, min_length=1, max_length=255)


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
    email: Optional[str] = None
    phone_number: Optional[str] = None
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
    chapters_per_week: int = Field(default=2, ge=1, le=53)


class UpdateGroupRequest(BaseModel):
    """Request body for updating group settings."""
    chapters_per_week: Optional[int] = Field(None, ge=1, le=53)
    current_week: Optional[int] = Field(None, ge=1)


class SetMemberRoleRequest(BaseModel):
    """Request to change a member's role."""
    user_id: str
    role: str = Field(..., pattern="^(admin|group_lead|member)$")


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
    chapters_per_week: int = 2
    current_week: int = 1
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
    week_number: int = Field(default=1, ge=1)
    scheduled_date: Optional[datetime] = None


class AutoScheduleRequest(BaseModel):
    """Request to auto-schedule upcoming chapters for the group."""
    group_id: str
    # First chapter number to start scheduling from
    start_chapter: int = Field(default=1, ge=1)
    # How many weeks ahead to schedule
    weeks_ahead: int = Field(default=4, ge=1, le=12)


class AssignmentResponse(BaseModel):
    """Assignment data."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    user_id: str
    user_name: Optional[str] = None
    chapter_id: int
    chapter_number: Optional[int] = None
    chapter_title: Optional[str] = None
    week_number: int = 1
    scheduled_date: Optional[datetime] = None
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


# ─── Chat Schemas ─────────────────────────────────────────────────────────────


class SendMessageRequest(BaseModel):
    """Request to post a message in a group chat."""
    content: str = Field(..., min_length=1, max_length=2000)


class GroupMessageResponse(BaseModel):
    """A single group chat message."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    user_id: str
    user_name: str
    content: str
    created_at: datetime


# ─── Highlight Comment Schemas ────────────────────────────────────────────────


class PostHighlightCommentRequest(BaseModel):
    """Request to post a comment on a highlighted verse/paragraph."""
    chapter_id: int
    highlighted_text: str = Field(..., min_length=1, max_length=500)
    paragraph_index: int = Field(default=0, ge=0)
    comment: str = Field(..., min_length=1, max_length=2000)


class HighlightCommentResponse(BaseModel):
    """A comment anchored to a highlighted verse in a chapter."""
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    user_id: str
    user_name: str
    chapter_id: int
    chapter_number: Optional[int] = None
    highlighted_text: str
    paragraph_index: int
    comment: str
    created_at: datetime
