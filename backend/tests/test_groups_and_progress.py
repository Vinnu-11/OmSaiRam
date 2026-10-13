# Om Sai Ram
# Tests for groups, assignments, and progress endpoints.
# Covers corner cases and edge conditions.

import os

os.environ["DATABASE_URL"] = "sqlite://"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import Chapter

# In-memory SQLite
engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base.metadata.create_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


def _register_and_get_token(name="Test User", email="test@test.com", password="password123"):
    """Helper: register a user and return the access token."""
    response = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": password},
    )
    return response.json()["access_token"]


def _auth_header(token):
    """Helper: create auth header dict."""
    return {"Authorization": f"Bearer {token}"}


def _seed_chapters():
    """Seed test chapters into the database."""
    db = TestingSessionLocal()
    for i in range(1, 54):
        chapter = Chapter(
            number=i,
            title=f"Chapter {i}",
            content=f"Content of chapter {i}",
            language="en",
            version=1,
        )
        db.add(chapter)
    db.commit()
    db.close()


# ─── Group Tests ──────────────────────────────────────────────────────────────


class TestGroupCreation:
    """Tests for creating groups."""

    def test_create_group_success(self):
        token = _register_and_get_token("Group Creator", "creator@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "Sai Bhaktas", "description": "Our reading group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "Sai Bhaktas"
        assert data["mode"] == "chapter_wise"
        assert data["member_count"] == 1  # Creator is auto-added
        assert len(data["invite_code"]) == 6

    def test_create_group_saptah_mode(self):
        token = _register_and_get_token("Saptah User", "saptah@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "Weekly Group", "mode": "saptah"},
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        assert response.json()["mode"] == "saptah"

    def test_create_group_invalid_mode(self):
        token = _register_and_get_token("Invalid Mode", "invalid_mode@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "Bad Group", "mode": "invalid"},
            headers=_auth_header(token),
        )
        assert response.status_code == 422

    def test_create_group_empty_name(self):
        token = _register_and_get_token("Empty Name", "empty_name@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        assert response.status_code == 422

    def test_create_group_unauthenticated(self):
        response = client.post(
            "/api/v1/groups",
            json={"name": "No Auth", "mode": "chapter_wise"},
        )
        assert response.status_code == 403

    def test_create_group_very_long_name(self):
        token = _register_and_get_token("Long Name", "longname@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "A" * 256, "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        assert response.status_code == 422


class TestGroupJoining:
    """Tests for joining groups via invite code."""

    def test_join_group_success(self):
        # Create a group
        token1 = _register_and_get_token("Admin", "admin_join@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Join Test Group", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        invite_code = create_response.json()["invite_code"]

        # Another user joins
        token2 = _register_and_get_token("Joiner", "joiner@test.com")
        response = client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token2),
        )
        assert response.status_code == 200
        assert response.json()["member_count"] == 2

    def test_join_group_invalid_code(self):
        token = _register_and_get_token("Invalid Code", "invalidcode@test.com")
        response = client.post(
            "/api/v1/groups/join",
            json={"invite_code": "XXXXXX"},
            headers=_auth_header(token),
        )
        assert response.status_code == 404

    def test_join_group_already_member(self):
        # Create and try to join own group
        token = _register_and_get_token("Self Join", "selfjoin@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Self Join Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        invite_code = create_response.json()["invite_code"]

        response = client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token),
        )
        assert response.status_code == 400
        assert "already a member" in response.json()["detail"]

    def test_join_group_short_code(self):
        token = _register_and_get_token("Short Code", "shortcode@test.com")
        response = client.post(
            "/api/v1/groups/join",
            json={"invite_code": "AB"},
            headers=_auth_header(token),
        )
        assert response.status_code == 422


class TestGroupDetail:
    """Tests for getting group details."""

    def test_get_group_detail_member(self):
        token = _register_and_get_token("Detail User", "detail@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Detail Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        group_id = create_response.json()["id"]

        response = client.get(
            f"/api/v1/groups/{group_id}",
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        data = response.json()
        assert data["group"]["name"] == "Detail Group"
        assert len(data["members"]) == 1
        assert data["members"][0]["role"] == "admin"

    def test_get_group_detail_non_member(self):
        # Create a group with one user
        token1 = _register_and_get_token("Owner", "owner_detail@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Private Group", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        group_id = create_response.json()["id"]

        # Another user tries to access
        token2 = _register_and_get_token("Outsider", "outsider@test.com")
        response = client.get(
            f"/api/v1/groups/{group_id}",
            headers=_auth_header(token2),
        )
        assert response.status_code == 403

    def test_get_nonexistent_group(self):
        token = _register_and_get_token("Ghost", "ghost@test.com")
        response = client.get(
            "/api/v1/groups/nonexistent-id",
            headers=_auth_header(token),
        )
        assert response.status_code == 403  # Not a member of nonexistent group


class TestGroupDeletion:
    """Tests for leaving and deleting groups."""

    def test_admin_cannot_leave(self):
        token = _register_and_get_token("Admin Leave", "admin_leave@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Admin Leave Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        group_id = create_response.json()["id"]

        response = client.delete(
            f"/api/v1/groups/{group_id}/leave",
            headers=_auth_header(token),
        )
        assert response.status_code == 400
        assert "Admin" in response.json()["detail"]

    def test_member_can_leave(self):
        # Create group
        token1 = _register_and_get_token("Admin ML", "admin_ml@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Leave Test", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        invite_code = create_response.json()["invite_code"]
        group_id = create_response.json()["id"]

        # Join then leave
        token2 = _register_and_get_token("Leaver", "leaver@test.com")
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token2),
        )
        response = client.delete(
            f"/api/v1/groups/{group_id}/leave",
            headers=_auth_header(token2),
        )
        assert response.status_code == 204

    def test_non_admin_cannot_delete(self):
        # Create group with admin
        token1 = _register_and_get_token("Admin ND", "admin_nd@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "No Delete", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        invite_code = create_response.json()["invite_code"]
        group_id = create_response.json()["id"]

        # Another user joins and tries to delete
        token2 = _register_and_get_token("Non Admin", "nonadmin@test.com")
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token2),
        )
        response = client.delete(
            f"/api/v1/groups/{group_id}",
            headers=_auth_header(token2),
        )
        assert response.status_code == 403


# ─── Assignment Tests ─────────────────────────────────────────────────────────


class TestAssignments:
    """Tests for chapter assignments."""

    @classmethod
    def setup_class(cls):
        """Seed chapters for assignment tests."""
        _seed_chapters()

    def test_create_assignment_success(self):
        # Create group with admin
        token1 = _register_and_get_token("Assign Admin", "assign_admin@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Assignment Group", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        group_id = create_response.json()["id"]
        invite_code = create_response.json()["invite_code"]

        # Add a member
        token2 = _register_and_get_token("Assignee", "assignee@test.com")
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token2),
        )

        # Get user ID from /me
        me_response = client.get("/api/v1/auth/me", headers=_auth_header(token2))
        user_id = me_response.json()["id"]

        # Assign chapter 1
        response = client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": user_id, "chapter_id": 1},
            headers=_auth_header(token1),
        )
        assert response.status_code == 201
        data = response.json()
        assert data["chapter_id"] == 1
        assert data["status"] == "not_started"

    def test_non_admin_cannot_assign(self):
        # Create group
        token1 = _register_and_get_token("Admin NA", "admin_na@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "No Assign Group", "mode": "chapter_wise"},
            headers=_auth_header(token1),
        )
        group_id = create_response.json()["id"]
        invite_code = create_response.json()["invite_code"]

        # Member tries to assign
        token2 = _register_and_get_token("Member NA", "member_na@test.com")
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token2),
        )

        me = client.get("/api/v1/auth/me", headers=_auth_header(token2))
        response = client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": me.json()["id"], "chapter_id": 1},
            headers=_auth_header(token2),
        )
        assert response.status_code == 403

    def test_assign_nonexistent_chapter(self):
        token = _register_and_get_token("Bad Chapter", "badchapter@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Bad Chapter Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        group_id = create_response.json()["id"]
        me = client.get("/api/v1/auth/me", headers=_auth_header(token))

        response = client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": me.json()["id"], "chapter_id": 999},
            headers=_auth_header(token),
        )
        assert response.status_code == 404

    def test_duplicate_assignment_rejected(self):
        token = _register_and_get_token("Dup Assign", "dupassign@test.com")
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Dup Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        group_id = create_response.json()["id"]
        me = client.get("/api/v1/auth/me", headers=_auth_header(token))
        user_id = me.json()["id"]

        # First assignment succeeds
        client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": user_id, "chapter_id": 2},
            headers=_auth_header(token),
        )
        # Duplicate fails
        response = client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": user_id, "chapter_id": 2},
            headers=_auth_header(token),
        )
        assert response.status_code == 400
        assert "already assigned" in response.json()["detail"]


# ─── Progress Tests ───────────────────────────────────────────────────────────


class TestProgress:
    """Tests for reading progress updates."""

    def _setup_assignment(self):
        """Helper: creates a group, assigns a chapter, returns (token, assignment_id)."""
        token = _register_and_get_token(
            f"Progress User {os.urandom(4).hex()}",
            f"progress_{os.urandom(4).hex()}@test.com",
        )
        create_response = client.post(
            "/api/v1/groups",
            json={"name": "Progress Group", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        group_id = create_response.json()["id"]
        me = client.get("/api/v1/auth/me", headers=_auth_header(token))
        user_id = me.json()["id"]

        assign_response = client.post(
            "/api/v1/assignments",
            json={"group_id": group_id, "user_id": user_id, "chapter_id": 3},
            headers=_auth_header(token),
        )
        return token, assign_response.json()["id"]

    def test_update_progress_to_in_progress(self):
        token, assignment_id = self._setup_assignment()
        response = client.patch(
            f"/api/v1/progress/{assignment_id}",
            json={"status": "in_progress"},
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        assert response.json()["status"] == "in_progress"

    def test_update_progress_to_completed(self):
        token, assignment_id = self._setup_assignment()
        response = client.patch(
            f"/api/v1/progress/{assignment_id}",
            json={"status": "completed"},
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        assert response.json()["status"] == "completed"

    def test_invalid_status_rejected(self):
        token, assignment_id = self._setup_assignment()
        response = client.patch(
            f"/api/v1/progress/{assignment_id}",
            json={"status": "invalid_status"},
            headers=_auth_header(token),
        )
        assert response.status_code == 422

    def test_cannot_update_others_progress(self):
        token1, assignment_id = self._setup_assignment()
        # Another user tries to update
        token2 = _register_and_get_token(
            "Other User",
            f"other_{os.urandom(4).hex()}@test.com",
        )
        response = client.patch(
            f"/api/v1/progress/{assignment_id}",
            json={"status": "completed"},
            headers=_auth_header(token2),
        )
        assert response.status_code == 403

    def test_progress_nonexistent_assignment(self):
        token = _register_and_get_token(
            "No Assign",
            f"noassign_{os.urandom(4).hex()}@test.com",
        )
        response = client.patch(
            "/api/v1/progress/nonexistent-id",
            json={"status": "completed"},
            headers=_auth_header(token),
        )
        assert response.status_code == 404


# ─── Content Tests ────────────────────────────────────────────────────────────


class TestContent:
    """Tests for content/chapter endpoints."""

    def test_get_content_version(self):
        response = client.get("/api/v1/content/versions?language=en")
        assert response.status_code == 200
        data = response.json()
        assert data["language"] == "en"
        assert data["total_chapters"] == 53

    def test_get_chapters_list(self):
        response = client.get("/api/v1/content/chapters/en")
        assert response.status_code == 200
        chapters = response.json()
        assert len(chapters) == 53
        assert chapters[0]["number"] == 1

    def test_get_single_chapter(self):
        response = client.get("/api/v1/content/chapters/en/1")
        assert response.status_code == 200
        assert response.json()["number"] == 1
        assert response.json()["title"] == "Chapter 1"

    def test_get_nonexistent_chapter(self):
        response = client.get("/api/v1/content/chapters/en/99")
        assert response.status_code == 404

    def test_get_unsupported_language(self):
        response = client.get("/api/v1/content/versions?language=fr")
        assert response.status_code == 200
        assert response.json()["total_chapters"] == 0

    def test_content_endpoints_no_auth_required(self):
        """Content endpoints should be publicly accessible."""
        response = client.get("/api/v1/content/versions")
        assert response.status_code == 200

        response = client.get("/api/v1/content/chapters/en")
        assert response.status_code == 200


# ─── Edge Cases & Security Tests ─────────────────────────────────────────────


class TestEdgeCases:
    """Corner cases and security edge tests."""

    def test_expired_token_rejected(self):
        """Tokens with tampered payload should be rejected."""
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYWtlIiwiZXhwIjoxMDAwMDAwMDAwLCJ0eXBlIjoiYWNjZXNzIn0.invalid"},
        )
        assert response.status_code == 401

    def test_sql_injection_in_email(self):
        """SQL injection attempts in email should be rejected by validation."""
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "'; DROP TABLE users; --", "password": "password123"},
        )
        assert response.status_code == 422  # Invalid email format

    def test_xss_in_group_name(self):
        """XSS attempts in group name should be stored as plain text (no rendering)."""
        token = _register_and_get_token("XSS Test", f"xss_{os.urandom(4).hex()}@test.com")
        response = client.post(
            "/api/v1/groups",
            json={"name": "<script>alert('xss')</script>", "mode": "chapter_wise"},
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        # Value is stored as-is (API returns JSON, no HTML rendering)
        assert response.json()["name"] == "<script>alert('xss')</script>"

    def test_very_long_password(self):
        """Extremely long passwords should be handled gracefully."""
        response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Long Pass",
                "email": f"longpass_{os.urandom(4).hex()}@test.com",
                "password": "a" * 129,  # Over max length
            },
        )
        assert response.status_code == 422

    def test_unicode_in_name(self):
        """Unicode characters in names should work correctly."""
        token = _register_and_get_token("श्री साई", f"unicode_{os.urandom(4).hex()}@test.com")
        me = client.get("/api/v1/auth/me", headers=_auth_header(token))
        assert me.status_code == 200
        assert me.json()["name"] == "श्री साई"

    def test_empty_body_requests(self):
        """Requests with empty bodies should return 422."""
        response = client.post("/api/v1/auth/register", json={})
        assert response.status_code == 422

        response = client.post("/api/v1/auth/login", json={})
        assert response.status_code == 422

    def test_list_groups_when_empty(self):
        """New user with no groups should get an empty list."""
        token = _register_and_get_token(
            "No Groups",
            f"nogroups_{os.urandom(4).hex()}@test.com",
        )
        response = client.get("/api/v1/groups", headers=_auth_header(token))
        assert response.status_code == 200
        assert response.json()["groups"] == []

    def test_case_insensitive_email_login(self):
        """Email login should be case-insensitive (stored lowercase by Pydantic)."""
        email = f"CasE_{os.urandom(4).hex()}@Test.COM"
        client.post(
            "/api/v1/auth/register",
            json={"name": "Case Test", "email": email, "password": "password123"},
        )
        response = client.post(
            "/api/v1/auth/login",
            json={"email": email.lower(), "password": "password123"},
        )
        # Pydantic normalizes EmailStr to lowercase
        assert response.status_code == 200


# ─── Auto-Schedule & Suggest Tests ────────────────────────────────────────────


def _create_group_with_members(n_members=3, chapters_per_week=2, start_chapter=1):
    """Helper: create a group with n_members and return (admin_token, group_id, user_ids)."""
    admin_token = _register_and_get_token(
        f"Admin {os.urandom(4).hex()}",
        f"admin_{os.urandom(4).hex()}@test.com",
    )
    resp = client.post(
        "/api/v1/groups",
        json={
            "name": "Schedule Group",
            "mode": "chapter_wise",
            "chapters_per_week": chapters_per_week,
            "start_chapter": start_chapter,
        },
        headers=_auth_header(admin_token),
    )
    group_id = resp.json()["id"]
    admin_id = client.get("/api/v1/auth/me", headers=_auth_header(admin_token)).json()["id"]
    user_ids = [admin_id]

    for i in range(n_members - 1):
        token = _register_and_get_token(
            f"Member {i}_{os.urandom(4).hex()}",
            f"member_{os.urandom(4).hex()}@test.com",
        )
        invite_code = resp.json()["invite_code"]
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(token),
        )
        uid = client.get("/api/v1/auth/me", headers=_auth_header(token)).json()["id"]
        user_ids.append(uid)

    return admin_token, group_id, user_ids


class TestAutoSchedule:
    """Tests for auto-schedule endpoint."""

    def test_auto_schedule_independent_mode(self):
        """Independent mode assigns unique non-overlapping slices."""
        token, group_id, user_ids = _create_group_with_members(3, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={
                "group_id": group_id,
                "start_chapter": 1,
                "weeks_ahead": 1,
                "schedule_mode": "independent",
                "remainder_mode": "manual",
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        data = response.json()
        assignments = data["assignments"]
        # 3 members × 2 chapters each = 6 assignments
        assert len(assignments) == 6
        chapter_nums = sorted(a["chapter_number"] for a in assignments)
        assert chapter_nums == [1, 2, 3, 4, 5, 6]

    def test_auto_schedule_synchronized_mode(self):
        """Synchronized mode assigns the same chapters to all members."""
        token, group_id, user_ids = _create_group_with_members(2, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={
                "group_id": group_id,
                "start_chapter": 1,
                "weeks_ahead": 1,
                "schedule_mode": "synchronized",
                "remainder_mode": "manual",
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        assignments = response.json()["assignments"]
        # Both members get Ch.1 and Ch.2
        per_user = {}
        for a in assignments:
            per_user.setdefault(a["user_id"], []).append(a["chapter_number"])
        for uid, chapters in per_user.items():
            assert sorted(chapters) == [1, 2]

    def test_auto_schedule_multiple_weeks(self):
        """Scheduling multiple weeks creates assignments for each week."""
        token, group_id, _ = _create_group_with_members(2, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={
                "group_id": group_id,
                "start_chapter": 1,
                "weeks_ahead": 3,
                "schedule_mode": "synchronized",
                "remainder_mode": "manual",
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        assignments = response.json()["assignments"]
        weeks = set(a["week_number"] for a in assignments)
        assert len(weeks) == 3

    def test_auto_schedule_cycle_remainder(self):
        """Cycle mode wraps chapter numbers past the end back to Ch.1."""
        token, group_id, _ = _create_group_with_members(1, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={
                "group_id": group_id,
                "start_chapter": 53,
                "weeks_ahead": 1,
                "schedule_mode": "independent",
                "remainder_mode": "cycle",
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 201
        assignments = response.json()["assignments"]
        chapter_nums = sorted(a["chapter_number"] for a in assignments)
        # Ch.53 belongs to the combined 51-53 unit; the next unit wraps to 1.
        assert chapter_nums == [1, 51]
        assert next(a for a in assignments if a["chapter_number"] == 51)["chapter_label"] == "51-53"

    def test_auto_schedule_no_duplicate_on_rerun(self):
        """Running auto-schedule twice doesn't create duplicate assignments."""
        token, group_id, _ = _create_group_with_members(1, chapters_per_week=2)
        payload = {
            "group_id": group_id,
            "start_chapter": 1,
            "weeks_ahead": 1,
            "schedule_mode": "independent",
            "remainder_mode": "manual",
        }
        resp1 = client.post("/api/v1/assignments/auto-schedule", json=payload, headers=_auth_header(token))
        resp2 = client.post("/api/v1/assignments/auto-schedule", json=payload, headers=_auth_header(token))
        assert resp1.status_code == 201
        assert resp2.status_code == 201
        # Second run creates 0 new assignments (already exist)
        assert len(resp2.json()["assignments"]) == 0

    def test_auto_schedule_non_admin_forbidden(self):
        """Regular members cannot auto-schedule."""
        token, group_id, user_ids = _create_group_with_members(2)
        member_token = _register_and_get_token(
            f"NonAdmin {os.urandom(4).hex()}",
            f"nonadmin_{os.urandom(4).hex()}@test.com",
        )
        # Join the group as a regular member
        invite_code = client.get(
            f"/api/v1/groups/{group_id}",
            headers=_auth_header(token),
        ).json()["group"]["invite_code"]
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(member_token),
        )
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={"group_id": group_id, "start_chapter": 1, "weeks_ahead": 1},
            headers=_auth_header(member_token),
        )
        assert response.status_code == 403

    def test_auto_schedule_nonexistent_group(self):
        token = _register_and_get_token(
            f"NoGroup {os.urandom(4).hex()}",
            f"nogroup_{os.urandom(4).hex()}@test.com",
        )
        response = client.post(
            "/api/v1/assignments/auto-schedule",
            json={"group_id": "nonexistent", "start_chapter": 1, "weeks_ahead": 1},
            headers=_auth_header(token),
        )
        assert response.status_code == 403


class TestSuggestSchedule:
    """Tests for the smart-suggest endpoint."""

    def test_suggest_non_overlapping_pattern(self):
        """Two hints with step=W detected as non_overlapping."""
        token, group_id, _ = _create_group_with_members(3, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/suggest",
            json={
                "group_id": group_id,
                "week_number": 1,
                "hints": [
                    {"position": 0, "chapter_start": 1},
                    {"position": 1, "chapter_start": 3},
                ],
                "weeks_ahead": 1,
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        data = response.json()
        assert data["detected_mode"] == "non_overlapping"
        assert data["detected_step"] == 2
        # Should have suggestions for all 3 members × 2 weeks (week 1 + 1 ahead)
        assert len(data["suggestions"]) == 6

    def test_suggest_dense_pattern(self):
        """Two hints with step=1 detected as dense."""
        token, group_id, _ = _create_group_with_members(3, chapters_per_week=2)
        response = client.post(
            "/api/v1/assignments/suggest",
            json={
                "group_id": group_id,
                "week_number": 1,
                "hints": [
                    {"position": 0, "chapter_start": 1},
                    {"position": 1, "chapter_start": 2},
                ],
                "weeks_ahead": 1,
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        assert response.json()["detected_mode"] == "dense"
        assert response.json()["detected_step"] == 1

    def test_suggest_too_few_hints(self):
        """Less than 2 hints should be rejected."""
        token, group_id, _ = _create_group_with_members(2)
        response = client.post(
            "/api/v1/assignments/suggest",
            json={
                "group_id": group_id,
                "week_number": 1,
                "hints": [{"position": 0, "chapter_start": 1}],
                "weeks_ahead": 1,
            },
            headers=_auth_header(token),
        )
        assert response.status_code == 422

    def test_suggest_non_admin_forbidden(self):
        """Regular members cannot use suggest."""
        token, group_id, _ = _create_group_with_members(2)
        member_token = _register_and_get_token(
            f"Suggest NonAdmin {os.urandom(4).hex()}",
            f"suggestna_{os.urandom(4).hex()}@test.com",
        )
        invite_code = client.get(
            f"/api/v1/groups/{group_id}",
            headers=_auth_header(token),
        ).json()["group"]["invite_code"]
        client.post(
            "/api/v1/groups/join",
            json={"invite_code": invite_code},
            headers=_auth_header(member_token),
        )
        response = client.post(
            "/api/v1/assignments/suggest",
            json={
                "group_id": group_id,
                "week_number": 1,
                "hints": [
                    {"position": 0, "chapter_start": 1},
                    {"position": 1, "chapter_start": 3},
                ],
            },
            headers=_auth_header(member_token),
        )
        assert response.status_code == 403


class TestAdvanceWeek:
    """Tests for advance-week endpoint."""

    def test_advance_week_success(self):
        token, group_id, _ = _create_group_with_members(1)
        response = client.post(
            f"/api/v1/assignments/advance-week/{group_id}",
            headers=_auth_header(token),
        )
        assert response.status_code == 200
        assert response.json()["current_week"] == 2

    def test_advance_week_increments(self):
        token, group_id, _ = _create_group_with_members(1)
        client.post(f"/api/v1/assignments/advance-week/{group_id}", headers=_auth_header(token))
        resp = client.post(f"/api/v1/assignments/advance-week/{group_id}", headers=_auth_header(token))
        assert resp.json()["current_week"] == 3


class TestRegressions:
    """Bugs found in QA pass."""

    def test_group_lifecycle_corner_cases(self):
        token, group_id, user_ids = _create_group_with_members(2)
        member = _register_and_get_token("Late", f"late_{os.urandom(4).hex()}@test.com")
        code = client.get(f"/api/v1/groups/{group_id}", headers=_auth_header(token)).json()["group"]["invite_code"]
        # Invite codes are case/space-insensitive
        assert client.post("/api/v1/groups/join", json={"invite_code": f" {code.lower()} "}, headers=_auth_header(member)).status_code == 200

        client.post("/api/v1/assignments/auto-schedule", json={"group_id": group_id, "weeks_ahead": 1}, headers=_auth_header(token))
        aid = client.get(f"/api/v1/assignments/group/{group_id}", headers=_auth_header(token)).json()[0]["id"]
        # Non-members cannot read progress
        outsider = _register_and_get_token("Out", f"out_{os.urandom(4).hex()}@test.com")
        assert client.get(f"/api/v1/progress/{aid}", headers=_auth_header(outsider)).status_code == 403
        # Whitespace-only chat is rejected
        assert client.post(f"/api/v1/groups/{group_id}/messages", json={"content": "   "}, headers=_auth_header(token)).status_code == 422
        # Deleting assignments/groups with progress rows must not 500
        assert client.delete(f"/api/v1/assignments/{aid}", headers=_auth_header(token)).status_code == 204
        assert client.delete(f"/api/v1/groups/{group_id}", headers=_auth_header(token)).status_code == 204

    def test_profile_cannot_drop_login_email(self):
        token = _register_and_get_token("Keep", f"keep_{os.urandom(4).hex()}@test.com")
        assert client.patch("/api/v1/auth/me", json={"email": None}, headers=_auth_header(token)).status_code == 400
        assert client.patch("/api/v1/auth/me", json={"name": None}, headers=_auth_header(token)).status_code == 400

    def test_phone_signup_retry_with_name_reuses_otp(self, caplog):
        import logging, re
        phone = "+91" + str(7000000000 + int.from_bytes(os.urandom(3), "big"))
        with caplog.at_level(logging.INFO, logger="app.routers.auth"):
            client.post("/api/v1/auth/phone/send-otp", json={"phone_number": phone})
        otp = re.search(r": (\d{6}) ", caplog.text).group(1)
        body = {"phone_number": phone, "otp": otp}
        assert client.post("/api/v1/auth/phone/verify-otp", json=body).status_code == 404
        assert client.post("/api/v1/auth/phone/verify-otp", json={**body, "name": "Neo"}).status_code == 200

    def test_brute_force_is_rate_limited(self):
        email = f"bf_{os.urandom(4).hex()}@test.com"
        _register_and_get_token("BF", email)
        codes = [client.post("/api/v1/auth/login", json={"email": email, "password": "wrongpass1"}).status_code for _ in range(11)]
        assert codes[:10] == [401] * 10 and codes[10] == 429

        phone = "+91" + str(7000000000 + int.from_bytes(os.urandom(3), "big"))
        client.post("/api/v1/auth/phone/send-otp", json={"phone_number": phone})
        codes = [client.post("/api/v1/auth/phone/verify-otp", json={"phone_number": phone, "otp": "000000"}).status_code for _ in range(6)]
        assert codes[5] == 429

    def test_delete_account_and_member_cleanup(self):
        token, group_id, _ = _create_group_with_members(1)
        email = f"del_{os.urandom(4).hex()}@test.com"
        member = _register_and_get_token("Del", email)
        code = client.get(f"/api/v1/groups/{group_id}", headers=_auth_header(token)).json()["group"]["invite_code"]
        client.post("/api/v1/groups/join", json={"invite_code": code}, headers=_auth_header(member))
        client.post("/api/v1/assignments/auto-schedule", json={"group_id": group_id, "weeks_ahead": 1}, headers=_auth_header(token))

        # Admin must hand over / delete groups first
        assert client.delete("/api/v1/auth/me", headers=_auth_header(token)).status_code == 400
        assert client.delete("/api/v1/auth/me", headers=_auth_header(member)).status_code == 204
        assert client.get("/api/v1/auth/me", headers=_auth_header(member)).status_code == 401
        assert client.post("/api/v1/auth/login", json={"email": email, "password": "password123"}).status_code == 401
        names = [m["name"] for m in client.get(f"/api/v1/groups/{group_id}", headers=_auth_header(token)).json()["members"]]
        assert "Del" not in names
        assigned = {a["user_id"] for a in client.get(f"/api/v1/assignments/group/{group_id}", headers=_auth_header(token)).json()}
        assert len(assigned) == 1
