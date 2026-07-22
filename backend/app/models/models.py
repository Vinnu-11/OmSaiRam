# Om Sai Ram
# SQLAlchemy models — database table definitions.

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    String,
    Integer,
    Text,
    DateTime,
    ForeignKey,
    Enum as SqlEnum,
)
from sqlalchemy.orm import relationship

from ..database import Base


def generate_uuid() -> str:
    """Generate a new UUID string for primary keys."""
    return str(uuid.uuid4())


class User(Base):
    """Registered user of the application."""

    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String(255), unique=True, nullable=True, index=True)  # nullable for phone-only users
    phone_number = Column(String(20), unique=True, nullable=True, index=True)
    name = Column(String(255), nullable=False)
    password_hash = Column(String(255), nullable=True)  # Null for social/phone auth users
    auth_provider = Column(String(50), default="email")  # email, google, apple, phone
    avatar_url = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    memberships = relationship("GroupMember", back_populates="user")


class Group(Base):
    """A reading group of devotees."""

    __tablename__ = "groups"

    id = Column(String, primary_key=True, default=generate_uuid)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    mode = Column(String(20), nullable=False, default="chapter_wise")  # chapter_wise, saptah
    invite_code = Column(String(8), unique=True, nullable=False, index=True)
    created_by = Column(String, ForeignKey("users.id"), nullable=False)
    # How many chapters to assign per week (2 or 3). Used for auto-scheduling.
    chapters_per_week = Column(Integer, default=2)
    # Current reading week number (1-based). Auto-increments each week.
    current_week = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")
    assignments = relationship("ReadingAssignment", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    """Association between a user and a group."""

    __tablename__ = "group_members"

    id = Column(String, primary_key=True, default=generate_uuid)
    group_id = Column(String, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    role = Column(String(20), default="member")  # admin, group_lead, member
    joined_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="memberships")
    group = relationship("Group", back_populates="members")


class Chapter(Base):
    """A chapter of the Sai Satcharita."""

    __tablename__ = "chapters"

    id = Column(Integer, primary_key=True, autoincrement=True)
    number = Column(Integer, nullable=False, index=True)
    title = Column(String(500), nullable=False)
    content = Column(Text, nullable=False)
    language = Column(String(10), default="en")
    version = Column(Integer, default=1)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    assignments = relationship("ReadingAssignment", back_populates="chapter")


class ReadingAssignment(Base):
    """Assignment of a chapter to a user within a group."""

    __tablename__ = "reading_assignments"

    id = Column(String, primary_key=True, default=generate_uuid)
    group_id = Column(String, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    chapter_id = Column(Integer, ForeignKey("chapters.id"), nullable=False)
    # Which week this assignment belongs to (for weekly scheduling)
    week_number = Column(Integer, default=1)
    # The Monday of the week this chapter should be read
    scheduled_date = Column(DateTime, nullable=True)
    assigned_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    group = relationship("Group", back_populates="assignments")
    chapter = relationship("Chapter", back_populates="assignments")
    progress = relationship("ReadingProgress", back_populates="assignment", uselist=False)


class ReadingProgress(Base):
    """Tracks reading progress for an assignment."""

    __tablename__ = "reading_progress"

    id = Column(String, primary_key=True, default=generate_uuid)
    assignment_id = Column(String, ForeignKey("reading_assignments.id", ondelete="CASCADE"), nullable=False, unique=True)
    status = Column(String(20), default="not_started")  # not_started, in_progress, completed
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    assignment = relationship("ReadingAssignment", back_populates="progress")


class GroupMessage(Base):
    """A chat message posted to a group."""

    __tablename__ = "group_messages"

    id = Column(String, primary_key=True, default=generate_uuid)
    group_id = Column(String, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User")
    group = relationship("Group")


class PhoneOtp(Base):
    """One-time password sent to a phone number for authentication."""

    __tablename__ = "phone_otps"

    id = Column(String, primary_key=True, default=generate_uuid)
    phone_number = Column(String(20), nullable=False, index=True)
    otp_hash = Column(String(255), nullable=False)
    # True once this OTP has been successfully verified
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class Festival(Base):
    """An upcoming festival/event scraped from sai.org.in/en/festivals."""

    __tablename__ = "festivals"

    id = Column(String, primary_key=True, default=generate_uuid)
    title = Column(String(255), nullable=False)
    date_label = Column(String(100), nullable=False)   # e.g. "Tuesday, July 28, 2026"
    event_date = Column(DateTime, nullable=True)        # parsed date for sorting
    description = Column(Text, nullable=True)
    source_url = Column(String(500), default="https://sai.org.in/en/festivals")
    scraped_at = Column(DateTime, default=datetime.utcnow)
    created_at = Column(DateTime, default=datetime.utcnow)


class GroupNotificationSchedule(Base):
    """Notification schedule set by the group lead for weekly reading reminders.

    Controls:
    - When the initial 'start reading' reminder fires each week.
    - When the reading deadline is (day+hour within the assignment week).
    - Whether escalating reminders are enabled as the deadline approaches.
    """

    __tablename__ = "group_notification_schedules"

    id = Column(String, primary_key=True, default=generate_uuid)
    group_id = Column(
        String, ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False, unique=True, index=True,
    )
    # Days from assignment's scheduled_date (Monday=0) when reading starts.
    # e.g. 0 = notify Monday morning, 1 = Tuesday morning, etc.
    initial_reminder_day_offset = Column(Integer, default=0)   # 0 = Monday
    initial_reminder_hour = Column(Integer, default=9)          # 9 AM
    initial_reminder_minute = Column(Integer, default=0)

    # Days from scheduled_date when the reading deadline falls.
    # e.g. 6 = Sunday (end of the week).
    deadline_day_offset = Column(Integer, default=6)            # Sunday
    deadline_hour = Column(Integer, default=22)                 # 10 PM
    deadline_minute = Column(Integer, default=0)

    # Whether to send escalating reminders as the deadline approaches.
    escalation_enabled = Column(Boolean, default=True)

    created_by = Column(String, ForeignKey("users.id"), nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    group = relationship("Group")


class ChapterHighlightComment(Base):
    """A comment tied to a highlighted paragraph/verse in a chapter, shared with the group."""

    __tablename__ = "chapter_highlight_comments"

    id = Column(String, primary_key=True, default=generate_uuid)
    group_id = Column(String, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    chapter_id = Column(Integer, ForeignKey("chapters.id"), nullable=False)
    # The highlighted text snippet (up to 500 chars) so it can be shown in context
    highlighted_text = Column(String(500), nullable=False)
    # Zero-based paragraph index within the chapter for scroll-to navigation
    paragraph_index = Column(Integer, nullable=False, default=0)
    comment = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User")
    chapter = relationship("Chapter")
    group = relationship("Group")
