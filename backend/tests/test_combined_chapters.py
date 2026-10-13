"""Combined translation chapters must consume one scheduling slot."""

import pytest
from datetime import datetime, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Chapter, Group, GroupMember, User
from app.routers.assignments import auto_schedule, create_assignment, suggest_schedule
from app.schemas import AutoScheduleRequest, CreateAssignmentRequest, SuggestScheduleRequest
from fastapi import HTTPException


@pytest.fixture
def reading_group():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine)() as db:
        user = User(name="Lead", email="combined@test.com")
        db.add(user)
        db.flush()
        group = Group(name="Combined chapters", created_by=user.id,
                      invite_code="COMBIN", chapters_per_week=1, current_week=1)
        db.add(group)
        db.flush()
        db.add(GroupMember(group_id=group.id, user_id=user.id, role="admin"))
        db.add_all([Chapter(id=n, number=n, title=f"Chapter {n}",
                            content="", language="mr") for n in range(1, 54)])
        db.commit()
        yield db, user, group
    engine.dispose()


@pytest.mark.parametrize("mode", ["independent", "rotating_window", "dense_window", "synchronized"])
def test_combined_chapters_advance_as_one_slot(reading_group, mode):
    db, user, group = reading_group
    result = auto_schedule(AutoScheduleRequest(group_id=group.id, start_chapter=15,
                          weeks_ahead=4, schedule_mode=mode), user, db)
    assert [a.chapter_number for a in result["assignments"]] == [15, 16, 18, 20]
    assert [a.chapter_label for a in result["assignments"]] == ["15", "16-17", "18-19", "20"]


@pytest.mark.parametrize("start,expected", [(17, [16, 18]), (19, [18, 20]),
                                           (44, [43, 45]), (52, [51, 1]), (53, [51, 1])])
def test_start_inside_range_and_cycle(reading_group, start, expected):
    db, user, group = reading_group
    result = auto_schedule(AutoScheduleRequest(group_id=group.id, start_chapter=start,
                          weeks_ahead=2, remainder_mode="cycle"), user, db)
    assert [a.chapter_number for a in result["assignments"]] == expected


def test_manual_assignment_normalizes_and_rejects_combined_duplicate(reading_group):
    db, user, group = reading_group
    result = create_assignment(CreateAssignmentRequest(group_id=group.id,
                               user_id=user.id, chapter_id=17), user, db)
    assert result.chapter_number == 16
    assert result.chapter_label == "16-17"
    with pytest.raises(HTTPException) as exc:
        create_assignment(CreateAssignmentRequest(group_id=group.id,
                          user_id=user.id, chapter_id=16), user, db)
    assert exc.value.status_code == 400


def test_suggestions_count_combined_units(reading_group):
    db, user, group = reading_group
    result = suggest_schedule(SuggestScheduleRequest(group_id=group.id,
                             hints=[{"position": 0, "chapter_start": 16},
                                    {"position": 1, "chapter_start": 18}],
                             weeks_ahead=2), user, db)
    assert result.detected_step == 1
    assert [s.chapter_numbers for s in result.suggestions] == [[16], [18], [20]]


def test_multi_slot_assignment_and_truncation(reading_group):
    db, user, group = reading_group
    group.chapters_per_week = 2
    result = auto_schedule(AutoScheduleRequest(group_id=group.id, start_chapter=49,
                          weeks_ahead=2, remainder_mode="truncate"), user, db)
    assert [a.chapter_number for a in result["assignments"]] == [49, 50, 51]
    assert result["remainder_chapters"]


@pytest.mark.parametrize("mode,expected", [
    ("independent", [16, 18, 20, 21]),
    ("rotating_window", [16, 18, 18, 20]),
    ("dense_window", [16, 18, 18, 20]),
    ("synchronized", [16, 16, 18, 18]),
])
def test_combined_units_across_members(reading_group, mode, expected):
    db, user, group = reading_group
    member = User(name="Member", email="member@test.com")
    db.add(member)
    db.flush()
    db.add(GroupMember(group_id=group.id, user_id=member.id, role="member"))
    db.commit()
    result = auto_schedule(AutoScheduleRequest(group_id=group.id, start_chapter=16,
                          weeks_ahead=2, schedule_mode=mode), user, db)
    assert [a.chapter_number for a in result["assignments"]] == expected


def test_manual_assignments_can_repeat_in_different_weeks(reading_group):
    db, user, group = reading_group
    first = create_assignment(CreateAssignmentRequest(group_id=group.id,
                              user_id=user.id, chapter_id=16, week_number=1), user, db)
    second = create_assignment(CreateAssignmentRequest(group_id=group.id,
                               user_id=user.id, chapter_id=17, week_number=2), user, db)
    assert first.chapter_number == second.chapter_number == 16
    assert second.week_number == 2


def test_manual_assignment_gets_selected_weeks_monday(reading_group):
    db, user, group = reading_group
    group.current_week = 3
    result = create_assignment(CreateAssignmentRequest(group_id=group.id,
                               user_id=user.id, chapter_id=20, week_number=5), user, db)
    now = datetime.utcnow()
    monday = (now - timedelta(days=now.weekday()) + timedelta(weeks=2)).replace(
        hour=0, minute=0, second=0, microsecond=0)
    assert result.scheduled_date == monday


def test_manual_assignment_preserves_explicit_date(reading_group):
    db, user, group = reading_group
    date = datetime(2026, 11, 2)
    result = create_assignment(CreateAssignmentRequest(group_id=group.id,
                               user_id=user.id, chapter_id=20,
                               scheduled_date=date), user, db)
    assert result.scheduled_date == date