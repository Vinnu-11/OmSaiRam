"""Independent catalogue API subchecks; run from backend with Python 3.10+.

No application lifespan, network, production database or existing tests are used.
Every scenario/permission-matrix cell has a fresh SQLite database with FK checks.
Exit 1 means observed product failures, not that execution stopped early.
Evidence deliberately excludes raw responses, credentials, OTP values and hashes.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import logging
import os
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

# Must precede all application imports; even the unused app engine is in-memory.
os.environ["DATABASE_URL"] = "sqlite://"
os.environ["DEBUG"] = "true"
os.environ["JWT_SECRET_KEY"] = "isolated-catalogue-fixture-not-a-production-secret"

from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.middleware.auth import create_access_token, create_refresh_token, hash_password
from app.models import (Chapter, ChapterHighlightComment, Group, GroupMember,
                        GroupMessage, GroupNotificationSchedule, PhoneOtp,
                        ReadingAssignment, ReadingProgress, User)
from app.routers import auth

PREFIX = "/api/v1"
PASSWORD = "fixture-password-only"
NEW_PASSWORD = "changed-fixture-password"
OTP = "406182"
OTHER_OTP = "975304"
UNITS = [n for n in range(1, 54) if n not in (17, 19, 44, 52, 53)]
RESULTS: list[dict] = []
SECRETS = {PASSWORD, NEW_PASSWORD, OTP, OTHER_OTP}
SCOPE = "Partial catalogue evidence: direct API/SQLite only; no UI, device, PostgreSQL concurrency or external integration certification"


def redact(value):
    """Defense in depth; raw request secrets are never added to the evidence."""
    if isinstance(value, dict):
        sensitive = {"password", "password_hash", "current_password", "new_password",
                     "token", "access_token", "refresh_token", "id_token", "otp", "otp_hash",
                     "authorization", "secret", "jwt_secret_key"}
        # Catalogue keys such as OTP-01 are identifiers, not credential fields.
        return {k: "[REDACTED]" if k.lower() in sensitive else redact(v)
                for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [redact(v) for v in value]
    if isinstance(value, str):
        for secret in SECRETS:
            value = value.replace(secret, "[REDACTED]")
        return re.sub(r"eyJ[\w-]+\.[\w-]+\.[\w-]+", "[REDACTED-JWT]", value)
    return value


class Fixture:
    def __init__(self, name):
        self.name = name
        self.trace = []
        self.engine = create_engine("sqlite://", connect_args={"check_same_thread": False},
                                    poolclass=StaticPool)
        @event.listens_for(self.engine, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine, expire_on_commit=False)
        self.db = self.Session()
        self.users = {}
        for role in ("A", "L", "M1", "M2", "X", "P"):
            user = User(id=role, name=f"Fixture {role}",
                        email=None if role == "P" else f"{role.lower()}@example.com",
                        phone_number="+919876543210" if role == "P" else None,
                        password_hash=None if role == "P" else PASSWORD_HASH,
                        auth_provider="phone" if role == "P" else "email")
            self.db.add(user)
            self.users[role] = user
        self.db.add_all(Chapter(id=100+n, number=n, title=f"Chapter {n}",
                               content="Fixture scripture", language="mr") for n in range(1, 54))
        self.db.commit()
        for gid, owner in (("G1", "A"), ("G2", "X")):
            self.db.add(Group(id=gid, name=gid, created_by=owner,
                              invite_code="ABC123" if gid == "G1" else "XYZ456",
                              current_week=1, chapters_per_week=2, start_chapter=1))
        self.db.commit()
        for i, (role, membership) in enumerate((("A", "admin"), ("L", "group_lead"),
                                               ("M1", "member"), ("M2", "member"))):
            self.db.add(GroupMember(group_id="G1", user_id=role, role=membership,
                                    joined_at=datetime(2026, 1, 1)+timedelta(seconds=i)))
        self.db.add(GroupMember(group_id="G2", user_id="X", role="admin"))
        self.db.commit()
        self.tokens = {r: create_access_token(r) for r in self.users}
        self.refresh = {r: create_refresh_token(r) for r in self.users}
        SECRETS.update(self.tokens.values())
        SECRETS.update(self.refresh.values())
        auth._attempts.clear()
        def override():
            with self.Session() as session:
                yield session
        app.dependency_overrides[get_db] = override
        # Not a context manager: app lifespan would scrape/seed the default DB.
        self.client = TestClient(app, raise_server_exceptions=False)

    def close(self):
        self.client.close()
        app.dependency_overrides.clear()
        auth._attempts.clear()
        self.db.close()
        self.engine.dispose()

    def request(self, method, path, role="A", body=None, **kwargs):
        headers = kwargs.pop("headers", {})
        if role:
            headers.setdefault("Authorization", "Bearer " + self.tokens[role])
        self.trace.append({"method": method, "path": path, "actor": role or "Guest",
                           "body": redact(body)})
        response = self.client.request(method, PREFIX+path, json=body, headers=headers, **kwargs)
        self.trace[-1]["http_status"] = response.status_code
        return response

    def check(self, cases, name, actual, expected, ok=None):
        for case in cases.split():
            RESULTS.append(redact({"case_id": case, "check_name": name,
                "status": "Pass" if (actual == expected if ok is None else ok) else "Fail",
                "expected": expected, "actual": actual, "scope": SCOPE,
                "scenario": self.name, "reproduction": list(self.trace)}))

    def http(self, cases, name, response, expected):
        self.check(cases, name, response.status_code, expected)
        return response.json() if response.status_code in (200, 201) else {}

    def count(self, model, **filters):
        self.db.expire_all()
        return self.db.query(model).filter_by(**filters).count()

    def fingerprint(self):
        """Compare all table values, not just counts; never emit raw values."""
        self.db.expire_all()
        state = []
        for table in sorted(Base.metadata.tables.values(), key=lambda t: t.name):
            rows = self.db.execute(table.select()).all()
            state.append((table.name, sorted(tuple(str(v) for v in row) for row in rows)))
        return hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()

    def assign(self, user="M1", chapter=1, week=1, group="G1", **extra):
        return self.request("POST", "/assignments", body={"group_id": group,
            "user_id": user, "chapter_id": 100+chapter, "week_number": week, **extra})

    def populate(self):
        assignment = self.assign().json()
        message = self.request("POST", "/groups/G1/messages", "M1", {"content": "Fixture message"}).json()
        highlight = self.request("POST", "/groups/G1/highlights", "M1", {
            "chapter_id": 101, "highlighted_text": "Fixture text", "comment": "Fixture comment"}).json()
        self.request("PUT", "/groups/G1/notification-schedule", body={})
        return assignment["id"], message["id"], highlight["id"]


def run(name, cases, function):
    fixture = None
    try:
        fixture = Fixture(name)
        function(fixture)
    except Exception as exc:
        # Do not print exception text; validation exceptions can contain secrets.
        if fixture:
            fixture.check(cases, "Scenario execution completed", type(exc).__name__, "No runner exception")
        else:
            for case in cases.split():
                RESULTS.append({"case_id": case, "check_name": "Fixture setup", "status": "Fail",
                                "expected": "Fresh isolated fixture", "actual": type(exc).__name__,
                                "scope": SCOPE, "scenario": name, "reproduction": []})
    finally:
        if fixture:
            fixture.close()


def authentication(f):
    body = {"email": "new@example.com", "name": "  भक्त  ", "password": PASSWORD}
    data = f.http("AUTH-01 AUTH-02", "Unicode signup and name trimming", f.request("POST", "/auth/register", None, body), 201)
    f.check("AUTH-01", "Exactly one signup account", f.count(User, email="new@example.com"), 1)
    f.check("AUTH-02", "Whitespace trimmed; Unicode retained", data.get("user", {}).get("name"), "भक्त")
    f.http("AUTH-03 AUTH-04", "Case-normalized duplicate email", f.request("POST", "/auth/register", None,
        {**body, "email": "NEW@example.com"}), 400)
    for name, accepted in (("", False), ("   ", False), ("a", True), ("名"*255, True), ("a"*256, False)):
        f.http("AUTH-02", f"Signup name length {len(name)}", f.request("POST", "/auth/register", None,
            {**body, "email": f"name{len(f.trace)}@example.com", "name": name}), 201 if accepted else 422)
    for email in ("", "bad", "a@", "x"*255+"@example.com"):
        f.http("AUTH-03", "Invalid email boundary", f.request("POST", "/auth/register", None, {**body, "email": email}), 422)
    for password in ("", "a"*7, "a"*8, "a"*128, "a"*129, " "*8, "भ"*8):
        SECRETS.add(password) if password else None
        f.http("AUTH-05", f"Signup password character length {len(password)}", f.request("POST", "/auth/register", None,
            {**body, "email": f"length{len(f.trace)}@example.com", "password": password}),
            201 if 8 <= len(password) <= 128 else 422)
    f.http("AUTH-07", "Mixed-case login", f.request("POST", "/auth/login", None,
        {"email": "A@EXAMPLE.COM", "password": PASSWORD}), 200)
    wrong = f.request("POST", "/auth/login", None, {"email": "a@example.com", "password": "wrong"})
    missing = f.request("POST", "/auth/login", None, {"email": "absent@example.com", "password": "wrong"})
    f.check("AUTH-08", "Generic credential failure avoids enumeration", [wrong.status_code, missing.status_code,
        wrong.json().get("detail") == missing.json().get("detail")], [401, 401, True])
    f.http("AUTH-19", "Google unconfigured, controlled no-session error", f.request("POST", "/auth/social", None,
        {"provider": "google", "id_token": "fixture"}), 501)
    f.http("AUTH-19", "Invalid social provider", f.request("POST", "/auth/social", None,
        {"provider": "unknown", "id_token": "fixture"}), 422)
    f.http("AUTH-20", "Apple unconfigured, controlled no-session error", f.request("POST", "/auth/social", None,
        {"provider": "apple", "id_token": "fixture"}), 400)
    f.check("AUTH-19 AUTH-20", "Social requests created no accounts", f.count(User, auth_provider="google")+
            f.count(User, auth_provider="apple"), 0)
    phone = {"name": "Phone", "phone_number": "+91 (98765) 43210", "password": PASSWORD}
    f.http("AUTH-04", "Duplicate normalized phone", f.request("POST", "/auth/register", None, phone), 400)


def tokens(f):
    expired = jwt.encode({"sub": "A", "type": "access", "exp": datetime.utcnow()-timedelta(seconds=5)},
                         settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    bad_algorithm = jwt.encode({"sub": "A", "type": "access", "exp": datetime.utcnow()+timedelta(minutes=5)},
                              settings.jwt_secret_key, algorithm="HS384")
    for label, token in (("malformed", "invalid"), ("expired", expired), ("tampered", f.tokens["A"]+"x"),
                         ("refresh used as access", f.refresh["A"]), ("algorithm mismatch", bad_algorithm)):
        f.http("AUTH-12 SEC-05", label, f.request("GET", "/auth/me", None,
            headers={"Authorization": "Bearer "+token}), 401)
    f.http("AUTH-12", "Missing access credentials", f.request("GET", "/auth/me", None), 403)
    refreshed = f.http("AUTH-13", "Valid refresh returns access", f.request("POST", "/auth/refresh", None,
        {"refresh_token": f.refresh["A"]}), 200)
    f.http("AUTH-13", "Returned access authenticates protected profile", f.request("GET", "/auth/me", None,
        headers={"Authorization": "Bearer "+refreshed.get("access_token", "")}), 200)
    for payload in ({"sub": "A", "type": "access"}, {"type": "refresh"},
                    {"sub": "A", "type": "unknown"}, {"sub": "A", "type": "refresh", "exp": 1},
                    {"sub": "absent", "type": "refresh"}):
        token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
        f.http("AUTH-16", "Invalid refresh claims", f.request("POST", "/auth/refresh", None, {"refresh_token": token}), 401)
    f.http("AUTH-16", "Malformed refresh", f.request("POST", "/auth/refresh", None, {"refresh_token": "bad"}), 401)
    f.http("AUTH-17 SEC-05", "Old refresh replay must be revoked after exchange (safety oracle)",
        f.request("POST", "/auth/refresh", None, {"refresh_token": f.refresh["A"]}), 401)
    f.http("PROFILE-04", "Password change", f.request("POST", "/auth/change-password", body={
        "current_password": PASSWORD, "new_password": NEW_PASSWORD}), 200)
    f.http("PROFILE-04", "Old password denied", f.request("POST", "/auth/login", None,
        {"email": "a@example.com", "password": PASSWORD}), 401)
    f.http("PROFILE-04", "New password accepted", f.request("POST", "/auth/login", None,
        {"email": "a@example.com", "password": NEW_PASSWORD}), 200)
    f.http("AUTH-17 SEC-05", "Retained access after password change must be revoked (safety oracle)", f.request("GET", "/auth/me"), 401)
    f.http("AUTH-17 SEC-05", "Retained refresh after password change must be revoked (safety oracle)",
        f.request("POST", "/auth/refresh", None, {"refresh_token": f.refresh["A"]}), 401)


def login_limit(f):
    with patch("app.routers.auth.time.monotonic") as clock:
        clock.return_value = 10000
        for attempt in range(10):
            f.http("AUTH-10", f"Failed login attempt {attempt+1}", f.request("POST", "/auth/login", None,
                {"email": "a@example.com", "password": "wrong"}), 401)
        f.http("AUTH-10", "Eleventh attempt throttled", f.request("POST", "/auth/login", None,
            {"email": "A@example.com", "password": PASSWORD}), 429)
        f.http("AUTH-10", "Independent identifier still allowed", f.request("POST", "/auth/login", None,
            {"email": "m1@example.com", "password": PASSWORD}), 200)
        clock.return_value = 10901
        f.http("AUTH-10", "Real limiter eviction after 901 seconds (not clear/reset)", f.request("POST", "/auth/login", None,
            {"email": "a@example.com", "password": PASSWORD}), 200)


def otp(f):
    phone = "+919876543210"
    # Controlled generator; plaintext never leaves the runtime or reaches evidence/logs.
    def send(code=OTP, formatted=phone):
        with patch("app.routers.auth.secrets.choice", side_effect=list(code)):
            return f.request("POST", "/auth/phone/send-otp", None, {"phone_number": formatted})
    def verify(number=phone, code=OTP, **extra):
        return f.request("POST", "/auth/phone/verify-otp", None, {"phone_number": number, "otp": code, **extra})
    f.http("OTP-01", "Formatted number accepted", send(formatted="+91 (98765) 43210"), 200)
    row = f.db.query(PhoneOtp).one()
    f.check("OTP-01", "Normalized phone and ten-minute expiry; hash-only persistence",
        [row.phone_number == phone, 599 <= (row.expires_at-row.created_at).total_seconds() <= 601,
         row.otp_hash != OTP, row.is_used], [True, True, True, False])
    for bad in ("", "123", "0"*10, "+"+"1"*16, "abcdefgh", "++919876543210"):
        f.http("OTP-02", "Invalid phone rejected", f.request("POST", "/auth/phone/send-otp", None, {"phone_number": bad}), 422)
    for value in ("123", "1234", "12345678", "123456789", "abcdef", "    "):
        f.http("OTP-06", f"Incorrect verification length {len(value)} (digit-only UI not certified)",
               verify(code=value), 422 if len(value) not in range(4, 9) else 401)
        auth._attempts.clear()  # Independent invalid-input parameters, not expiry test.
    f.http("OTP-05", "Wrong phone cannot use existing credential", verify("+919876543211"), 401)
    data = f.http("OTP-03", "Existing phone logs into same P", verify(), 200)
    f.check("OTP-03", "Existing account not duplicated", data.get("user", {}).get("id"), "P")
    f.http("OTP-05", "Used credential denied", verify(), 401)
    send()
    f.db.expire_all()
    current = f.db.query(PhoneOtp).filter_by(is_used=False).one()
    current.expires_at = datetime.utcnow()-timedelta(seconds=1)
    f.db.commit()
    f.http("OTP-05", "Actual expired database credential denied", verify(), 401)
    send(formatted="+919876543212")
    f.http("OTP-04", "New phone needs name", verify("+919876543212"), 404)
    f.check("OTP-04", "Name prompt did not consume credential", f.count(PhoneOtp, phone_number="+919876543212", is_used=False), 1)
    f.http("OTP-04", "Same credential with Unicode name creates account", verify("+919876543212", name="भक्त"), 200)


def otp_limit(f):
    phone = "+919876543210"
    with patch("app.routers.auth.secrets.choice", side_effect=list(OTP)):
        f.request("POST", "/auth/phone/send-otp", None, {"phone_number": phone})
    with patch("app.routers.auth.time.monotonic") as clock:
        clock.return_value = 10000
        for attempt in range(5):
            f.http("OTP-07", f"Failed verification attempt {attempt+1}", f.request("POST", "/auth/phone/verify-otp", None,
                {"phone_number": phone, "otp": OTHER_OTP}), 401)
        f.http("OTP-07", "Formatting does not bypass throttle", f.request("POST", "/auth/phone/verify-otp", None,
            {"phone_number": "+91 (98765) 43210", "otp": OTP}), 429)
        clock.return_value = 10601
        f.http("OTP-07", "Real limiter eviction after 601 seconds", f.request("POST", "/auth/phone/verify-otp", None,
            {"phone_number": phone, "otp": OTP}), 200)


def resend(f):
    phone = "+919876543210"
    def send(code):
        with patch("app.routers.auth.secrets.choice", side_effect=list(code)):
            return f.request("POST", "/auth/phone/send-otp", None, {"phone_number": phone})
    with patch("app.routers.auth.time.monotonic") as clock:
        clock.return_value = 10000
        send(OTP)
        send(OTHER_OTP)
        f.check("OTP-08", "Resend retains exactly newest unused record", f.count(PhoneOtp, phone_number=phone, is_used=False), 1)
        f.http("OTP-08", "Old credential invalidated", f.request("POST", "/auth/phone/verify-otp", None,
            {"phone_number": phone, "otp": OTP}), 401)
        f.http("OTP-08", "Newest credential accepted", f.request("POST", "/auth/phone/verify-otp", None,
            {"phone_number": phone, "otp": OTHER_OTP}), 200)
        for _ in range(3):
            f.http("OTP-08", "Send within five-per-hour allowance", send(OTP), 200)
        f.http("OTP-08", "Sixth send throttled", send(OTP), 429)
        clock.return_value = 13601
        f.http("OTP-08", "Send limiter real hour expiry", send(OTP), 200)


def profiles(f):
    data = f.http("PROFILE-01", "Own Unicode profile persists", f.request("PATCH", "/auth/me", "M1", {"name": "  भक्त  "}), 200)
    f.check("PROFILE-01", "Profile reload has updated name", f.request("GET", "/auth/me", "M1").json().get("name"), "भक्त")
    f.check("SEC-03", "Profile excludes hashes, credentials and OTP data", sorted(set(data) &
        {"password", "password_hash", "access_token", "refresh_token", "otp", "otp_hash"}), [])
    for body, expected in (({}, 400), ({"name": " "}, 422), ({"email": "bad"}, 422),
                           ({"phone_number": "bad"}, 422), ({"email": "a@example.com"}, 400),
                           ({"avatar_url": "x"*501}, 422), ({"name": None}, 400)):
        f.http("PROFILE-02", "Invalid profile patch rejected", f.request("PATCH", "/auth/me", "M1", body), expected)
    f.check("PROFILE-02", "Rejected patches preserved name", f.request("GET", "/auth/me", "M1").json().get("name"), "भक्त")
    for role, field in (("A", "email"), ("P", "phone_number")):
        f.http("PROFILE-03", "Cannot clear primary login identifier", f.request("PATCH", "/auth/me", role, {field: None}), 400)
    for role, old, new, expected in (("A", "wrong", NEW_PASSWORD, 401), ("P", PASSWORD, NEW_PASSWORD, 400),
                                   ("A", PASSWORD, "x"*7, 422), ("A", PASSWORD, "x"*129, 422)):
        f.http("PROFILE-05", "Password change credential/provider/boundary rejection", f.request("POST", "/auth/change-password", role,
            {"current_password": old, "new_password": new}), expected)
    f.http("PROFILE-08", "Admin deletion blocked", f.request("DELETE", "/auth/me"), 400)
    assignment, _, _ = f.populate()
    f.http("PROFILE-08 PROFILE-09 PROFILE-10 CHAT-11", "Eligible populated account anonymized", f.request("DELETE", "/auth/me", "M1"), 204)
    f.db.expire_all()
    user = f.db.get(User, "M1")
    f.check("PROFILE-09 PROFILE-10 CHAT-11", "All personal fields scrubbed", [user.name, user.auth_provider,
        user.email, user.phone_number, user.avatar_url, user.password_hash], ["Deleted user", "deleted", None, None, None, None])
    f.check("PROFILE-09", "Memberships assignments progress removed", [f.count(GroupMember, user_id="M1"),
        f.count(ReadingAssignment, user_id="M1"), f.count(ReadingProgress, assignment_id=assignment)], [0, 0, 0])
    for resource in ("messages", "highlights"):
        f.check("CHAT-11", "Retained content has anonymized author", f.request("GET", f"/groups/G1/{resource}").json()[0]["user_name"], "Deleted user")
    f.http("PROFILE-09 AUTH-14 SEC-05", "Deleted-user retained access denied", f.request("GET", "/auth/me", "M1"), 401)
    f.http("PROFILE-09 AUTH-14 SEC-05", "Deleted-user retained refresh denied", f.request("POST", "/auth/refresh", None,
        {"refresh_token": f.refresh["M1"]}), 401)


def groups(f):
    data = f.http("GRP-01", "Create defaults", f.request("POST", "/groups", body={"name": "New Group"}), 201)
    f.check("GRP-01", "Defaults and invite-code length", [data.get("current_week"), data.get("chapters_per_week"),
        data.get("start_chapter"), data.get("member_count"), len(data.get("invite_code", ""))], [1, 2, 1, 1, 6])
    f.check("GRP-01", "Creator automatically admin", f.count(GroupMember, group_id=data["id"], user_id="A", role="admin"), 1)
    for n in (0, 1, 255, 256):
        f.http("GRP-02", f"API group name length {n}", f.request("POST", "/groups", body={"name": "名"*n}), 201 if 1 <= n <=255 else 422)
    for n in (1000, 1001):
        f.http("GRP-02", f"Description length {n}", f.request("POST", "/groups", body={"name": "Boundary", "description": "x"*n}), 201 if n==1000 else 422)
    for field in ("chapters_per_week", "start_chapter"):
        for n in (0, 1, 53, 54):
            f.http("GRP-03", f"{field}={n}", f.request("POST", "/groups", body={"name": "Boundary", field: n}), 201 if 1<=n<=53 else 422)
    for mode in ("saptah", "invalid"):
        f.http("GRP-03", f"Mode {mode}", f.request("POST", "/groups", body={"name": "Mode", "mode": mode}), 201 if mode=="saptah" else 422)
    f.check("GRP-04", "List exposes only memberships", [g["id"] for g in f.request("GET", "/groups", "M1").json()["groups"]], ["G1"])
    f.check("GRP-04", "New phone user's list empty", f.request("GET", "/groups", "P").json()["groups"], [])
    f.http("GRP-05", "Join code trimmed/lowercase", f.request("POST", "/groups/join", "X", {"invite_code": " abc123 "}), 200)
    f.http("GRP-06", "Duplicate join controlled", f.request("POST", "/groups/join", "X", {"invite_code": "ABC123"}), 400)
    for n in (3, 4, 8, 9, 20, 21):
        f.http("GRP-06", f"Invite schema length {n}", f.request("POST", "/groups/join", "P", {"invite_code": "z"*n}), 404 if n in (4, 8) else 422)
    saved = f.assign().json()["id"]
    f.http("GRP-09", "Admin setting update", f.request("PATCH", "/groups/G1/settings", body={"chapters_per_week": 3, "start_chapter": 16, "current_week": 3}), 200)
    f.check("GRP-09", "Saved assignment not rewritten", f.db.get(ReadingAssignment, saved).week_number, 1)
    f.http("GRP-11", "Admin promotes member", f.request("PATCH", "/groups/G1/members/role", body={"user_id": "M2", "role": "group_lead"}), 200)
    f.http("GRP-11", "Self-demotion rejected", f.request("PATCH", "/groups/G1/members/role", body={"user_id": "A", "role": "member"}), 400)
    f.http("GRP-11", "Invalid role rejected", f.request("PATCH", "/groups/G1/members/role", body={"user_id": "M2", "role": "superuser"}), 422)
    f.http("GRP-11", "Nonmember role target rejected", f.request("PATCH", "/groups/G1/members/role", body={"user_id": "P", "role": "member"}), 404)
    f.http("GRP-15", "Lead cannot remove another lead", f.request("DELETE", "/groups/G1/members/M2", "L"), 403)
    f.http("GRP-15", "Admin can remove lead", f.request("DELETE", "/groups/G1/members/M2"), 204)
    f.http("GRP-15", "Admin self-removal blocked", f.request("DELETE", "/groups/G1/members/A"), 400)
    f.http("GRP-15", "Lead cannot remove admin", f.request("DELETE", "/groups/G1/members/A", "L"), 400)
    f.http("GRP-13", "Unknown user add rejected", f.request("POST", "/groups/G1/members", body={"user_id": "missing"}), 404)
    f.http("GRP-13", "Duplicate member add rejected", f.request("POST", "/groups/G1/members", body={"user_id": "M1"}), 400)


def search(f):
    for n in range(25):
        f.db.add(User(id=f"search{n}", name=f"Search Person {n}", email=f"search{n}@example.com",
                      phone_number=f"+9190000000{n:02}", auth_provider="email"))
    f.db.commit()
    f.check("GRP-12", "Short search empty", f.request("GET", "/groups/G1/search-users?q=s", "L").json(), [])
    data = f.request("GET", "/groups/G1/search-users?q=Search", "L").json()
    f.check("GRP-12", "Search results capped at 20", len(data), 20)
    f.check("GRP-12 SEC-03", "Contacts masked and existing members excluded", all("***" in d["email"] and
        d["phone_number"].startswith("***") and d["id"] not in ("A", "L", "M1", "M2") for d in data), True)
    f.http("GRP-12", "Lead adds registered search user", f.request("POST", "/groups/G1/members", "L", {"user_id": data[0]["id"]}), 201)
    f.check("GRP-12", "Added user excluded from search", data[0]["id"] in [d["id"] for d in f.request("GET", "/groups/G1/search-users?q=Search", "L").json()], False)


def leave_or_remove(f, role, remove):
    saved = f.assign(user=role).json()["id"]
    path = f"/groups/G1/members/{role}" if remove else "/groups/G1/leave"
    cases = "GRP-14 PROG-10 SEC-07" if remove else "GRP-16 PROG-10 SEC-07"
    f.http(cases, "Eligible member removal/leave", f.request("DELETE", path, "A" if remove else role), 204)
    f.check(cases, "Assignment/progress/membership cleanup", [f.count(ReadingAssignment, id=saved),
        f.count(ReadingProgress, assignment_id=saved), f.count(GroupMember, group_id="G1", user_id=role)], [0, 0, 0])
    f.http(cases, "Stale reader cannot complete removed assignment", f.request("PATCH", f"/progress/{saved}", role, {"status": "completed"}), 404)
    f.http(cases, "Retained session cannot read group", f.request("GET", "/groups/G1", role), 403)
    f.http(cases, "Retained session cannot post chat", f.request("POST", "/groups/G1/messages", role, {"content": "stale"}), 403)
    f.check(cases, "My assignments no longer contains removed reading", f.request("GET", "/assignments/my", role).json(), [])


def deletion(f):
    saved, _, _ = f.populate()
    f.http("GRP-17", "Admin deletes group populated with all FK children", f.request("DELETE", "/groups/G1"), 204)
    f.check("GRP-17", "All group-dependent rows removed with FK enforcement", [f.count(model, group_id="G1") for model in
        (GroupMember, ReadingAssignment, GroupMessage, ChapterHighlightComment, GroupNotificationSchedule)] +
        [f.count(Group, id="G1"), f.count(ReadingProgress, assignment_id=saved)], [0]*7)
    for role in ("A", "L", "M1", "M2"):
        f.http("GRP-17", "Former members denied deleted-group detail", f.request("GET", "/groups/G1", role), 403)


def manual(f):
    data = f.http("MAN-01 MAN-06", "Real server ID assignment creates not-started reading", f.assign(chapter=16), 201)
    f.check("MAN-01 MAN-06", "ID differs from number and initial status", [data.get("chapter_id"), data.get("chapter_number"), data.get("status")], [116, 16, "not_started"])
    f.http("MAN-08", "Interior combined duplicate rejected", f.assign(chapter=17), 400)
    f.http("MAN-09", "Same unit another member accepted", f.assign(user="M2", chapter=17), 201)
    f.http("MAN-09", "Same unit later week accepted", f.assign(chapter=17, week=2), 201)
    f.http("MAN-09", "Same unit another group accepted", f.request("POST", "/assignments", "X",
        {"group_id": "G2", "user_id": "X", "chapter_id": 117}), 201)
    for n, canonical, end in ((19, 18, 19), (44, 43, 44), (52, 51, 53), (53, 51, 53)):
        d = f.http("MAN-04 MAN-05", f"Interior {n} canonicalization", f.assign(chapter=n, week=n), 201)
        f.check("MAN-04 MAN-05", "Canonical range fields", [d.get("chapter_id"), d.get("chapter_number"), d.get("chapter_end_number")], [100+canonical, canonical, end])
    for n in (1, 8, 20):
        f.http("MAN-03", f"Nonconsecutive selected chapter {n}", f.assign(chapter=n, week=3), 201)
    f.check("MAN-03", "Only selected readings created", [a["chapter_number"] for a in
        f.request("GET", "/assignments/group/G1?week_number=3").json()], [1, 8, 20])
    for week in (0, -1, "nonnumeric", 1000000000):
        f.http("MAN-11", f"Week boundary {week}", f.assign(chapter=2, week=week), 422 if week !=1000000000 else 400)
    f.http("MAN-13", "Unknown chapter rejected", f.assign(chapter=9999), 404)
    f.http("MAN-13", "Nonmember rejected", f.assign(user="X"), 400)
    f.http("MAN-13", "Unknown group rejected", f.assign(group="missing"), 403)
    f.request("PATCH", "/groups/G1/settings", body={"current_week": 3})
    d = f.http("MAN-14", "Default date relative to chosen week", f.assign(chapter=10, week=5), 201)
    now = datetime.utcnow()
    monday = (now-timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)+timedelta(weeks=2)
    f.check("MAN-14", "Selected week Monday offset", d.get("scheduled_date"), monday.isoformat())
    d = f.http("MAN-14", "Explicit date preserved", f.assign(chapter=11, week=5, scheduled_date="2027-03-19T12:30:00"), 201)
    f.check("MAN-14", "Explicit timestamp unchanged", d.get("scheduled_date"), "2027-03-19T12:30:00")
    # Legacy interior schedule must block canonical duplicate without rewriting history.
    legacy = ReadingAssignment(group_id="G1", user_id="M1", chapter_id=117, week_number=6)
    f.db.add(legacy)
    f.db.commit()
    f.http("MAN-08", "Legacy interior blocks same-unit duplicate", f.assign(chapter=16, week=6), 400)


def schedule_fixture(f, n=3, w=2):
    ordered = ("A", "M1", "M2")[:n]
    f.db.query(GroupMember).filter_by(group_id="G1").delete()
    f.db.add_all(GroupMember(group_id="G1", user_id=user, role="admin" if user=="A" else "member",
        joined_at=datetime(2026, 1, 1)+timedelta(seconds=i)) for i, user in enumerate(ordered))
    f.db.get(Group, "G1").chapters_per_week = w
    f.db.commit()
    return ordered


def schedules(f, mode, start=1, n=3, w=2, cases="SCH-01"):
    members = schedule_fixture(f, n, w)
    response = f.request("POST", "/assignments/auto-schedule", body={"group_id": "G1", "start_chapter": start,
                         "weeks_ahead": 2, "schedule_mode": mode, "remainder_mode": "cycle"})
    data = f.http(cases, "Automatic schedule succeeds", response, 201)
    expected = []
    s = UNITS.index({17:16, 19:18, 44:43, 52:51, 53:51}.get(start, start))
    for k in range(2):
        for i, user in enumerate(members):
            offset = {"independent": k*n*w+i*w, "rotating_window": (k+i)*w,
                      "dense_window": k*w+i, "synchronized": k*w}[mode]
            for slot in range(w):
                expected.append([user, k+1, UNITS[(s+offset+slot)%48]])
    actual = [[a["user_id"], a["week_number"], a["chapter_number"]] for a in data.get("assignments", [])]
    f.check(cases, f"{mode} unit-position formula N={n} W={w} start={start}", actual, expected)
    repeated = f.http("SCH-11", "Repeated schedule succeeds idempotently", f.request("POST", "/assignments/auto-schedule", body={
        "group_id": "G1", "start_chapter": start, "weeks_ahead": 2, "schedule_mode": mode, "remainder_mode": "cycle"}), 201)
    f.check("SCH-11", "Identical rerun creates no duplicate", len(repeated.get("assignments", [])), 0)


def schedule_boundaries(f):
    schedule_fixture(f, 1, 2)
    body = {"group_id": "G1", "weeks_ahead": 1, "start_chapter": 1}
    for field, values in (("weeks_ahead", (0, 1, 12, 13)), ("start_chapter", (0, 54)),
                          ("schedule_mode", ("invalid",)), ("remainder_mode", ("invalid",))):
        for value in values:
            expected = 201 if field=="weeks_ahead" and value in (1, 12) else 201 if field=="start_chapter" and value==54 else 422
            f.http("SCH-06", f"Automatic schema {field}={value}", f.request("POST", "/assignments/auto-schedule", body={**body, field: value}), expected)
    f.request("DELETE", "/groups/G1")
    # No data from this scenario is reused by other boundary cases.


def remainder(f, mode):
    schedule_fixture(f, 1, 2)
    start = 53 if mode=="cycle" else 49
    cases = "SCH-08" if mode=="cycle" else "SCH-09 SCH-10"
    data = f.http(cases, f"Remainder mode {mode}", f.request("POST", "/assignments/auto-schedule", body={
        "group_id": "G1", "start_chapter": start, "weeks_ahead": 1 if mode=="cycle" else 2, "remainder_mode": mode}), 201)
    actual = [a["chapter_number"] for a in data.get("assignments", [])]
    expected = [51, 1] if mode=="cycle" else [49, 50, 51]
    f.check(cases, "Book-end allocations without phantom chapters", actual, expected)
    if mode in ("manual", "truncate"):
        f.check(cases, "One unassigned unit explicitly reported", len(data.get("remainder_chapters", [])), 1)
    if mode=="round_robin":
        f.check("SCH-10", "Documented round-robin extras wrap back instead of truncating", actual, [49, 50, 51, 1])
    if mode=="extend_last":
        f.check("SCH-10", "Unavailable last-member slot explicitly reported, not silently lost",
                len(data.get("remainder_chapters", [])), 1)


def cycle_large(f):
    schedule_fixture(f, 1, 53)
    d = f.http("SCH-12", "More slots than reading units", f.request("POST", "/assignments/auto-schedule", body={
        "group_id": "G1", "weeks_ahead": 1, "remainder_mode": "cycle"}), 201)
    actual = [a["chapter_number"] for a in d.get("assignments", [])]
    f.check("SCH-12", "Each member/week unit unique", [len(actual), len(set(actual))], [48, 48])
    f.check("SCH-12", "Reduced slot count explicitly explained by response metadata",
        {"requested": 53, "created": len(actual), "reported_unfilled": len(d.get("remainder_chapters", []))},
        {"requested": 53, "created": 48, "reported_unfilled": 5})


def suggestions(f, starts=(1, 3)):
    schedule_fixture(f, 3, 2)
    req = {"group_id": "G1", "week_number": 1, "weeks_ahead": 1,
           "hints": [{"position": i, "chapter_start": n} for i, n in enumerate(starts)]}
    d = f.http("SCH-14 SCH-18", "Suggestion preview accepted", f.request("POST", "/assignments/suggest", body=req), 200)
    step = UNITS.index(starts[1])-UNITS.index(starts[0])
    mode = "non_overlapping" if step==2 else "dense" if step==1 else "custom"
    f.check("SCH-14", "Detected mode and unit step", [d.get("detected_mode"), d.get("detected_step")], [mode, step])
    f.check("SCH-18", "Preview writes nothing", [f.count(ReadingAssignment), f.count(ReadingProgress)], [0, 0])
    confirmed = f.http("SCH-17", "Confirm using actual Flutter backendMode mapping", f.request("POST", "/assignments/auto-schedule", body={
        "group_id": "G1", "start_chapter": starts[0], "weeks_ahead": 2,
        "schedule_mode": "dense_window" if mode=="dense" else "independent"}), 201)
    preview = sorted([slot["user_id"], slot["week_number"], chapter] for slot in d.get("suggestions", []) for chapter in slot["chapter_numbers"])
    actual = sorted([a["user_id"], a["week_number"], a["chapter_number"]] for a in confirmed.get("assignments", []))
    f.check("SCH-17", f"Every confirmed cell equals preview ({mode}, step {step})", actual, preview)


def suggestion_invalid(f):
    schedule_fixture(f, 3, 1)
    req = {"group_id": "G1", "hints": [{"position": 0, "chapter_start": 16}, {"position": 1, "chapter_start": 18}], "weeks_ahead": 1}
    d = f.http("SCH-15", "Combined ranges use reading-unit step", f.request("POST", "/assignments/suggest", body=req), 200)
    f.check("SCH-15", "16 to 18 is step one", d.get("detected_step"), 1)
    for hints, case, label, expected in ((req["hints"][:1], "SCH-16", "Too few hints", 422),
        ([{"position": 0, "chapter_start": 1}, {"position": 99, "chapter_start": 3}], "SCH-16", "Nonexistent member position", 400),
        ([{"position": 0, "chapter_start": 1}, {"position": 0, "chapter_start": 3}], "SCH-16", "Duplicate member positions", 400),
        ([{"position": 0, "chapter_start": 3}, {"position": 1, "chapter_start": 1}], "SCH-15", "Reversed negative progression", 400)):
        f.http(case, label+" must reject ambiguous extrapolation", f.request("POST", "/assignments/suggest", body={**req, "hints": hints}), expected)


def progress(f):
    saved = f.assign().json()["id"]
    for state in ("in_progress", "completed", "not_started"):
        d = f.http("PROG-01 PROG-09"+(" PROG-05" if state=="completed" else ""), "Own progress transition "+state,
            f.request("PATCH", f"/progress/{saved}", "M1", {"status": state}), 200)
        f.check("PROG-01 PROG-09", "Reloaded status and unique row", [f.request("GET", f"/progress/{saved}", "M2").json().get("status"),
            f.count(ReadingProgress, assignment_id=saved), bool(d.get("updated_at"))], [state, 1, True])
    for role in ("A", "L", "M2", "X"):
        f.http("PROG-02", "Non-assignee cannot update even as admin/lead", f.request("PATCH", f"/progress/{saved}", role, {"status": "completed"}), 403)
    f.http("PROG-03", "Invalid status", f.request("PATCH", f"/progress/{saved}", "M1", {"status": "invalid"}), 422)
    f.http("PROG-03", "Missing assignment", f.request("GET", "/progress/missing", "M1"), 404)
    f.http("PROG-03", "Outsider cannot read progress", f.request("GET", f"/progress/{saved}", "X"), 403)
    f.db.query(ReadingProgress).filter_by(assignment_id=saved).delete()
    f.db.commit()
    f.http("PROG-03", "Missing progress read controlled", f.request("GET", f"/progress/{saved}", "M1"), 404)
    f.http("PROG-03", "Owner recreates missing progress", f.request("PATCH", f"/progress/{saved}", "M1", {"status": "completed"}), 200)
    f.http("PROG-08", "Lead deletes reading with progress", f.request("DELETE", f"/assignments/{saved}", "L"), 204)
    f.check("PROG-08", "Assignment and progress removed", [f.count(ReadingAssignment, id=saved), f.count(ReadingProgress, assignment_id=saved)], [0, 0])
    f.http("PROG-08", "Stale reader controlled not-found", f.request("GET", f"/progress/{saved}", "M1"), 404)


def chat(f):
    text = "भक्त 🙏\nSecond line"
    d = f.http("CHAT-01", "Unicode multiline message", f.request("POST", "/groups/G1/messages", "M1", {"content": text}), 201)
    f.check("CHAT-01", "Message author and text preserved", [d.get("user_id"), d.get("content")], ["M1", text])
    for n in (0, 1, 2000, 2001):
        f.http("CHAT-02", f"Message length {n}", f.request("POST", "/groups/G1/messages", "M1", {"content": "x"*n}), 201 if 1<=n<=2000 else 422)
    f.http("CHAT-02", "Whitespace-only message", f.request("POST", "/groups/G1/messages", "M1", {"content": "  "}), 422)
    for n in (0, 1, 100, 101):
        f.http("CHAT-05", f"Pagination limit {n}", f.request("GET", f"/groups/G1/messages?limit={n}"), 200 if n in (1, 100) else 422)
    for role in ("X", "M2"):
        f.http("CHAT-03", "Outsider/nonowner deletion denied", f.request("DELETE", f"/groups/G1/messages/{d['id']}", role), 403)
    f.http("CHAT-04 SEC-02", "Wrong-group message deletion", f.request("DELETE", f"/groups/G2/messages/{d['id']}", "X"), 404)
    f.http("CHAT-04", "Owner deletes own message", f.request("DELETE", f"/groups/G1/messages/{d['id']}", "M1"), 204)
    f.http("CHAT-04", "Missing message deletion", f.request("DELETE", "/groups/G1/messages/missing"), 404)
    highlight = {"chapter_id": 116, "highlighted_text": "Fixture verse", "paragraph_index": 0, "comment": text}
    h = f.http("CHAT-07", "Highlight uses real server chapter ID", f.request("POST", "/groups/G1/highlights", "M1", highlight), 201)
    f.check("CHAT-07", "Highlight chapter/source/comment preserved", [h.get("chapter_id"), h.get("chapter_number"),
        h.get("highlighted_text"), h.get("comment")], [116, 16, "Fixture verse", text])
    for field, values in (("highlighted_text", ("", " "*3, "x"*500, "x"*501)),
                          ("comment", ("", " "*3, "x"*2000, "x"*2001)), ("paragraph_index", (-1, 0)), ("chapter_id", (9999,))):
        for value in values:
            expected = 404 if field=="chapter_id" else 201 if field=="paragraph_index" and value==0 else 201 if isinstance(value, str) and len(value) in (500, 2000) else 422
            f.http("CHAT-08", "Highlight boundary "+field, f.request("POST", "/groups/G1/highlights", "M1", {**highlight, field: value}), expected)
    f.check("CHAT-09", "Chapter filter excludes unrelated entries", f.request("GET", "/groups/G1/highlights?chapter_id=101", "M2").json(), [])
    f.http("CHAT-09 SEC-02", "Wrong-group highlight delete", f.request("DELETE", f"/groups/G2/highlights/{h['id']}", "X"), 404)
    f.http("CHAT-09", "Nonowner highlight delete denied", f.request("DELETE", f"/groups/G1/highlights/{h['id']}", "M2"), 403)
    f.http("CHAT-09", "Lead moderation allowed", f.request("DELETE", f"/groups/G1/highlights/{h['id']}", "L"), 204)
    inert = "<script>alert('fixture')</script> '; DROP TABLE users; --"
    msg = f.http("CHAT-12 SEC-11", "Script/SQL-like text accepted only as literal data", f.request("POST", "/groups/G1/messages", "M1", {"content": inert}), 201)
    f.check("CHAT-12 SEC-11", "API stores literal text without SQL mutation (rendering untested)", [msg.get("content"), f.count(User)], [inert, 6])


def pagination(f):
    # Deliberately identical timestamps expose missing cursor tie-breakers.
    when = datetime(2026, 1, 1)
    f.db.add_all(GroupMessage(id=f"same{i}", group_id="G1", user_id="M1", content="Fixture", created_at=when) for i in range(3))
    f.db.add(GroupMessage(id="foreign", group_id="G2", user_id="X", content="Fixture", created_at=when+timedelta(days=1)))
    f.db.commit()
    first = f.request("GET", "/groups/G1/messages?limit=1", "M1").json()
    following = f.request("GET", f"/groups/G1/messages?limit=100&before_id={first[0]['id']}", "M1").json()
    f.check("CHAT-05", "Same-timestamp cursor does not lose messages", len(first)+len(following), 3)
    f.http("CHAT-05 SEC-02", "Cross-group cursor rejected instead of using another group's timestamp",
        f.request("GET", "/groups/G1/messages?before_id=foreign", "M1"), 404)
    f.http("CHAT-05", "Unknown cursor controlled not-found", f.request("GET", "/groups/G1/messages?before_id=missing", "M1"), 404)


def notifications(f):
    f.http("NOTIF-05", "No settings controlled not-found", f.request("GET", "/groups/G1/notification-schedule", "M1"), 404)
    first = f.http("NOTIF-04", "Lead creates reminder settings", f.request("PUT", "/groups/G1/notification-schedule", "L", {}), 200)
    body = {"initial_reminder_day_offset": 6, "initial_reminder_hour": 23, "initial_reminder_minute": 59,
            "deadline_day_offset": 0, "deadline_hour": 0, "deadline_minute": 0, "escalation_enabled": False}
    second = f.http("NOTIF-04", "Admin updates same schedule", f.request("PUT", "/groups/G1/notification-schedule", body=body), 200)
    f.check("NOTIF-04", "Single persisted settings row; member reads updated values", [first.get("id")==second.get("id"),
        f.count(GroupNotificationSchedule, group_id="G1"), all(f.request("GET", "/groups/G1/notification-schedule", "M1").json().get(k)==v for k,v in body.items())], [True, 1, True])
    for field in ("initial_reminder_day_offset", "deadline_day_offset", "initial_reminder_hour", "deadline_hour", "initial_reminder_minute", "deadline_minute"):
        maximum = 6 if "offset" in field else 23 if "hour" in field else 59
        for value in (-1, 0, maximum, maximum+1):
            f.http("NOTIF-05", f"{field}={value}", f.request("PUT", "/groups/G1/notification-schedule", body={field: value}), 200 if 0<=value<=maximum else 422)
    f.http("NOTIF-05", "Missing group schedule", f.request("GET", "/groups/missing/notification-schedule"), 404)


def matrix(f, role, action):
    saved, message, highlight = f.populate()
    cases = "SEC-01"
    allowed_read = role in ("M1", "L", "A")
    allowed_lead = role in ("L", "A")
    allowed_admin = role == "A"
    denied = 403
    routes = {
        "profile": ("GET", "/auth/me", None, role is not None, 200, ""),
        "list_groups": ("GET", "/groups", None, role is not None, 200, ""),
        "create_group": ("POST", "/groups", {"name": "Allowed creation"}, role is not None, 201, ""),
        "join_group": ("POST", "/groups/join", {"invite_code": "XYZ456"}, role is not None, 400 if role=="X" else 200, ""),
        "own_assignments": ("GET", "/assignments/my", None, role is not None, 200, ""),
        "group_detail": ("GET", "/groups/G1", None, allowed_read, 200, "GRP-07"),
        "group_assignments": ("GET", "/assignments/group/G1", None, allowed_read, 200, "GRP-07"),
        "read_progress": ("GET", f"/progress/{saved}", None, allowed_read, 200, "PROG-03"),
        "read_messages": ("GET", "/groups/G1/messages", None, allowed_read, 200, "CHAT-03"),
        "read_highlights": ("GET", "/groups/G1/highlights", None, allowed_read, 200, "CHAT-09"),
        "read_reminders": ("GET", "/groups/G1/notification-schedule", None, allowed_read, 200, "NOTIF-04"),
        "manual_assign": ("POST", "/assignments", {"group_id":"G1", "user_id":"M1", "chapter_id":108}, allowed_lead, 201, "MAN-01"),
        "auto_schedule": ("POST", "/assignments/auto-schedule", {"group_id":"G1", "weeks_ahead":1}, allowed_lead, 201, ""),
        "suggest": ("POST", "/assignments/suggest", {"group_id":"G1", "hints":[{"position":0,"chapter_start":1},{"position":1,"chapter_start":3}]}, allowed_lead, 200, ""),
        "advance_week": ("POST", "/assignments/advance-week/G1", None, allowed_lead, 200, "SCH-19"),
        "delete_assignment": ("DELETE", f"/assignments/{saved}", None, allowed_lead, 204, "PROG-08"),
        "search_users": ("GET", "/groups/G1/search-users?q=Fixture", None, allowed_lead, 200, "GRP-13"),
        "add_member": ("POST", "/groups/G1/members", {"user_id":"P"}, allowed_lead, 201, "GRP-13"),
        "remove_member": ("DELETE", "/groups/G1/members/M2", None, allowed_lead, 204, "GRP-14"),
        "settings": ("PATCH", "/groups/G1/settings", {"current_week":2}, allowed_admin, 200, "GRP-10"),
        "role": ("PATCH", "/groups/G1/members/role", {"user_id":"M2","role":"group_lead"}, allowed_admin, 200, "GRP-10"),
        "delete_group": ("DELETE", "/groups/G1", None, allowed_admin, 204, "GRP-10 GRP-17"),
        "leave": ("DELETE", "/groups/G1/leave", None, allowed_read, 400 if role=="A" else 204, "GRP-16"),
        "write_progress": ("PATCH", f"/progress/{saved}", {"status":"completed"}, role=="M1", 200, "PROG-02"),
        "send_message": ("POST", "/groups/G1/messages", {"content":"New message"}, allowed_read, 201, "CHAT-01 CHAT-03"),
        "send_highlight": ("POST", "/groups/G1/highlights", {"chapter_id":101,"highlighted_text":"Verse","comment":"Comment"}, allowed_read, 201, "CHAT-07 CHAT-09"),
        "delete_message": ("DELETE", f"/groups/G1/messages/{message}", None, allowed_read, 204, "CHAT-04"),
        "delete_highlight": ("DELETE", f"/groups/G1/highlights/{highlight}", None, allowed_read, 204, "CHAT-09"),
        "write_reminders": ("PUT", "/groups/G1/notification-schedule", {}, allowed_lead, 200, "NOTIF-04"),
        "delete_account": ("DELETE", "/auth/me", None, role is not None, 400 if role in ("A","X") else 204, "PROFILE-08"),
        "change_password": ("POST", "/auth/change-password", {"current_password":PASSWORD,"new_password":NEW_PASSWORD}, role is not None, 200, "PROFILE-04"),
        "update_profile": ("PATCH", "/auth/me", {"name":"Updated fixture"}, role is not None, 200, "PROFILE-01"),
    }
    method, path, body, allowed, success, additional = routes[action]
    # Nonmember leave is intentionally 404; guest is rejected by HTTPBearer first.
    expected = success if allowed else 404 if action=="leave" and role else denied
    before = f.fingerprint()
    f.http(cases+" "+additional, f"Permission matrix {role or 'Guest'}: {action}", f.request(method, path, role, body), expected)
    if not allowed:
        f.check("SEC-01", "Denied operation leaves all DB field values unchanged", f.fingerprint()==before, True)


def security(f):
    saved, _, _ = f.populate()
    f.http("SEC-02", "Other-group assignee cannot update guessed assignment", f.request("PATCH", f"/progress/{saved}", "X", {"status":"completed"}), 403)
    f.request("PATCH", "/groups/G1/members/role", body={"user_id":"L", "role":"member"})
    for method, path, body in (("POST", "/assignments", {"group_id":"G1","user_id":"M1","chapter_id":108}),
                              ("PUT", "/groups/G1/notification-schedule", {}),
                              ("GET", "/groups/G1/search-users?q=Fixture", None)):
        f.http("SEC-07", "Retained lead session loses revoked privilege", f.request(method, path, "L", body), 403)
    for body in ({}, {"name": None}, {"name": 42}, {"name": "x", "email": "bad", "password": None}):
        f.http("SEC-06", "Missing/null/wrong scalar input", f.request("POST", "/auth/register", None, body), 422)
    f.http("SEC-06", "Malformed JSON validation", f.request("POST", "/groups", content="{", headers={"Content-Type":"application/json"}), 422)
    f.http("SEC-06", "Unknown profile field cannot update privilege", f.request("PATCH", "/auth/me", "M1", {"auth_provider":"admin"}), 400)
    f.check("SEC-06", "Unknown field caused no auth-provider mutation", f.db.get(User, "M1").auth_provider, "email")
    allowed_origin = next((o for o in settings.cors_origins if o != "*"), "http://localhost:3000")
    for origin, allowed in (("https://untrusted.invalid", False), (allowed_origin, True)):
        response = f.client.options(PREFIX+"/groups", headers={"Origin": origin,
            "Access-Control-Request-Method":"GET", "Access-Control-Request-Headers":"authorization"})
        expected_origin = "*" if "*" in settings.cors_origins else origin
        f.check("SEC-08", "Configured allowed-origin preflight" if allowed else
            "Untrusted origin must be restricted (safety oracle; default wildcard is not production certification)",
            [response.status_code, response.headers.get("access-control-allow-origin")],
            [200, expected_origin] if allowed else [400, None])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="/tmp/omsairam-qa-api-results.json")
    args = parser.parse_args()
    global PASSWORD_HASH
    logging.disable(logging.CRITICAL)
    # Prevent third-party warnings/application logger output from exposing secrets.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        PASSWORD_HASH = hash_password(PASSWORD)
        scenarios = [("Signup validation", "AUTH-01", authentication), ("JWT lifecycle", "AUTH-12", tokens),
            ("Login throttle real expiry", "AUTH-10", login_limit), ("Phone lifecycle", "OTP-01", otp),
            ("Verification throttle real expiry", "OTP-07", otp_limit), ("Resend lifecycle", "OTP-08", resend),
            ("Profile deletion", "PROFILE-01", profiles), ("Groups CRUD", "GRP-01", groups),
            ("Authorized search", "GRP-12", search), ("Populated group deletion", "GRP-17", deletion),
            ("Manual readings", "MAN-01", manual), ("Automatic boundaries", "SCH-06", schedule_boundaries),
            ("Cycle more than unit count", "SCH-12", cycle_large), ("Suggestion validation", "SCH-15", suggestion_invalid),
            ("Progress lifecycle", "PROG-01", progress), ("Chat boundaries", "CHAT-01", chat),
            ("Chat tied timestamp cursors", "CHAT-05", pagination), ("Reminder server settings", "NOTIF-04", notifications),
            ("Contract and revoked roles", "SEC-01", security)]
        for name, cases, function in scenarios:
            run(name, cases, function)
        for role in ("M1", "L"):
            run(f"Leave cleanup {role}", "GRP-16", lambda f, r=role: leave_or_remove(f, r, False))
        run("Remove cleanup", "GRP-14", lambda f: leave_or_remove(f, "M1", True))
        for i, mode in enumerate(("independent", "rotating_window", "dense_window", "synchronized"), 1):
            run(mode, f"SCH-0{i}", lambda f, m=mode, c=f"SCH-0{i}": schedules(f, m, cases=c))
            for n in (1, 2, 3):
                for w in (1, 2, 3):
                    run(f"Unit formula {mode} N={n} W={w}", "SCH-05",
                        lambda f, m=mode, nn=n, ww=w: schedules(f, m, start=15, n=nn, w=ww, cases="SCH-05"))
        for mode in ("cycle", "manual", "truncate", "extend_last", "round_robin"):
            run("Book remainder "+mode, "SCH-10", lambda f, m=mode: remainder(f, m))
        for starts in ((1, 3), (1, 2), (1, 4)):
            run(f"Preview confirm hints {starts}", "SCH-17", lambda f, s=starts: suggestions(f, s))
        actions = ("profile", "list_groups", "create_group", "join_group", "own_assignments", "group_detail",
            "group_assignments", "read_progress", "read_messages", "read_highlights", "read_reminders",
            "manual_assign", "auto_schedule", "suggest", "advance_week", "delete_assignment", "search_users",
            "add_member", "remove_member", "settings", "role", "delete_group", "leave", "write_progress",
            "send_message", "send_highlight", "delete_message", "delete_highlight", "write_reminders",
            "delete_account", "change_password", "update_profile")
        for role in (None, "X", "M1", "L", "A"):
            for action in actions:
                run(f"Matrix {role or 'Guest'} {action}", "SEC-01", lambda f, r=role, a=action: matrix(f, r, a))
    by_case = defaultdict(list)
    for record in RESULTS:
        by_case[record["case_id"]].append(record)
    summary = {"subchecks": len(RESULTS), "subcheck_status": dict(Counter(r["status"] for r in RESULTS)),
        "catalogue_ids_with_partial_api_evidence": len(by_case),
        "case_status": {case: "Fail" if any(r["status"]=="Fail" for r in records) else "Pass (API subchecks only)"
                        for case, records in sorted(by_case.items())}}
    evidence = {"schema_version": 1, "executed_at_utc": datetime.utcnow().isoformat()+"Z",
        "runner": "backend/qa_catalogue_checks.py", "environment": {"database":"fresh in-memory SQLite per scenario",
            "foreign_keys": True, "chapter_ids":"101..153 != chapter numbers 1..53", "http":"in-process TestClient",
            "lifespan_started":False, "external_services":"not invoked", "rate_limiter":"cleared only between independent scenarios",
            "credentials":"synthetic, excluded from evidence"}, "scope": SCOPE,
        "limitations": ["Not ALL catalogue cases; no API subcheck is proof of UI/E2E case completion.",
            "No PostgreSQL cascades/concurrency, multi-worker rate limits, actual SMS, social-provider login or device reminder delivery.",
            "Refresh replay/password-change revocation use desired safety oracles; current stateless limitations are recorded as Fail.",
            "API accepts nonnumeric OTP length 4..8 at schema level but invalid verification returns 401; UI digit validation untested.",
            "Round-robin assertion uses documented wrapping behavior; extend-last has no approved allocation oracle, only accounting checked.",
            "CORS uses loaded app configuration; default wildcard fails the restricted-origin safety oracle, not a claim about deployed production settings.",
            "Invalid chat cursor rejection is a safety oracle against silently restarting pagination; actual responses are retained.",
            "Browser rendering of script-like stored text and deployment HTTPS remain untested."],
        "summary": summary, "results": RESULTS}
    sanitized = redact(evidence)
    text = json.dumps(sanitized, indent=2, ensure_ascii=False)
    compact = json.dumps(sanitized, separators=(",", ":"), ensure_ascii=False)
    # Validate output contains no credential literal/JWT; fail closed before writing.
    # Scan compact JSON: indentation itself matches an all-space password fixture.
    for secret in SECRETS:
        if secret and secret in compact:
            raise RuntimeError("Evidence redaction verification failed")
    Path(args.output).write_text(text+"\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    print("Evidence: "+args.output)
    return 1 if summary["subcheck_status"].get("Fail", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())