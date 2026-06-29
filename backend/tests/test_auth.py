# Om Sai Ram
# Tests for authentication endpoints.

import os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Override DATABASE_URL before importing app modules
os.environ["DATABASE_URL"] = "sqlite:///./test.db"
os.environ["JWT_SECRET_KEY"] = "test-secret-key"

from app.database import Base, get_db
from app.main import app

# Use in-memory SQLite for tests
SQLALCHEMY_DATABASE_URL = "sqlite://"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Create tables in test DB
Base.metadata.create_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db

client = TestClient(app)


class TestHealthCheck:
    """Tests for the health check endpoint."""

    def test_health_check(self):
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"


class TestRegistration:
    """Tests for user registration."""

    def test_register_success(self):
        response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Test User",
                "email": "test@example.com",
                "password": "securepassword123",
            },
        )
        assert response.status_code == 201
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["user"]["email"] == "test@example.com"
        assert data["user"]["name"] == "Test User"

    def test_register_duplicate_email(self):
        # First registration
        client.post(
            "/api/v1/auth/register",
            json={
                "name": "User One",
                "email": "duplicate@example.com",
                "password": "password123",
            },
        )
        # Second registration with same email
        response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "User Two",
                "email": "duplicate@example.com",
                "password": "password456",
            },
        )
        assert response.status_code == 400

    def test_register_invalid_email(self):
        response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Test",
                "email": "not-an-email",
                "password": "password123",
            },
        )
        assert response.status_code == 422

    def test_register_short_password(self):
        response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Test",
                "email": "short@example.com",
                "password": "short",
            },
        )
        assert response.status_code == 422


class TestLogin:
    """Tests for user login."""

    def test_login_success(self):
        # Register first
        client.post(
            "/api/v1/auth/register",
            json={
                "name": "Login Test",
                "email": "login@example.com",
                "password": "password123",
            },
        )
        # Login
        response = client.post(
            "/api/v1/auth/login",
            json={
                "email": "login@example.com",
                "password": "password123",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["user"]["email"] == "login@example.com"

    def test_login_wrong_password(self):
        response = client.post(
            "/api/v1/auth/login",
            json={
                "email": "login@example.com",
                "password": "wrongpassword",
            },
        )
        assert response.status_code == 401

    def test_login_nonexistent_user(self):
        response = client.post(
            "/api/v1/auth/login",
            json={
                "email": "noone@example.com",
                "password": "password123",
            },
        )
        assert response.status_code == 401


class TestTokenRefresh:
    """Tests for token refresh."""

    def test_refresh_token_success(self):
        # Register to get tokens
        register_response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Refresh Test",
                "email": "refresh@example.com",
                "password": "password123",
            },
        )
        refresh_token = register_response.json()["refresh_token"]

        # Use refresh token
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        assert response.status_code == 200
        assert "access_token" in response.json()

    def test_refresh_invalid_token(self):
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": "invalid-token"},
        )
        assert response.status_code == 401


class TestProtectedEndpoints:
    """Tests for authentication-protected endpoints."""

    def test_get_me_authenticated(self):
        # Register to get access token
        register_response = client.post(
            "/api/v1/auth/register",
            json={
                "name": "Protected Test",
                "email": "protected@example.com",
                "password": "password123",
            },
        )
        token = register_response.json()["access_token"]

        # Access protected endpoint
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 200
        assert response.json()["email"] == "protected@example.com"

    def test_get_me_unauthenticated(self):
        response = client.get("/api/v1/auth/me")
        assert response.status_code == 403  # No token provided
