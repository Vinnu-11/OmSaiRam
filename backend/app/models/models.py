# Om Sai Ram
# SQLAlchemy models — database table definitions.

import uuid
from datetime import datetime

from sqlalchemy import (
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
    email = Column(String(255), unique=True, nullable=False, index=True)
    name = Column(String(255), nullable=False)
    password_hash = Column(String(255), nullable=True)  # Null for social auth users
    auth_provider = Column(String(50), default="email")  # email, google, apple
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
    role = Column(String(20), default="member")  # admin, member
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
