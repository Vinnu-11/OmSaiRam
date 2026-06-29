# Om Sai Ram
# Auth router — registration, login, social auth, and token refresh.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..schemas import (
    RegisterRequest,
    LoginRequest,
    SocialAuthRequest,
    RefreshRequest,
    AuthResponse,
    UserResponse,
)
from ..middleware.auth import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
)

router = APIRouter()


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    """Register a new user with email and password.

    Returns user data and JWT tokens on success.
    Raises 400 if email is already registered.
    """
    # Normalize email to lowercase for case-insensitive matching
    email = request.email.lower()

    # Check if email already exists
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    # Create the user
    user = User(
        email=email,
        name=request.name,
        password_hash=hash_password(request.password),
        auth_provider="email",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # Generate tokens
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return AuthResponse(
        user=UserResponse.model_validate(user),
        access_token=access_token,
        refresh_token=refresh_token,
    )


@router.post("/login", response_model=AuthResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    """Authenticate with email and password.

    Returns user data and JWT tokens on success.
    Raises 401 if credentials are invalid.
    """
    email = request.email.lower()
    user = db.query(User).filter(User.email == email).first()
    if not user or not user.password_hash:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return AuthResponse(
        user=UserResponse.model_validate(user),
        access_token=access_token,
        refresh_token=refresh_token,
    )


@router.post("/social", response_model=AuthResponse)
def social_auth(request: SocialAuthRequest, db: Session = Depends(get_db)):
    """Authenticate via social provider (Google/Apple).

    Exchanges the provider's ID token for our JWT tokens.
    Creates a new account if the user doesn't exist yet.

    Note: In production, verify the ID token with the provider's API.
    """
    # TODO: Verify the ID token with Google/Apple's API
    # For now, we decode basic info from the token (placeholder logic)
    # In production, use google.oauth2.id_token.verify_oauth2_token()

    # For Google, extract email from the token (simplified)
    # Real implementation would verify the token cryptographically
    email = None
    if request.provider == "google":
        # Placeholder — replace with actual Google token verification
        # from google.oauth2 import id_token as google_id_token
        # info = google_id_token.verify_oauth2_token(request.id_token, ...)
        # email = info["email"]
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="Social auth token verification not yet configured. Set up Google/Apple OAuth credentials.",
        )

    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not extract email from token",
        )

    # Find or create user
    user = db.query(User).filter(User.email == email).first()
    if not user:
        user = User(
            email=email,
            name=request.name or email.split("@")[0],
            auth_provider=request.provider,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return AuthResponse(
        user=UserResponse.model_validate(user),
        access_token=access_token,
        refresh_token=refresh_token,
    )


@router.post("/refresh", response_model=AuthResponse)
def refresh_token(request: RefreshRequest, db: Session = Depends(get_db)):
    """Exchange a valid refresh token for new access and refresh tokens.

    Raises 401 if the refresh token is invalid or expired.
    """
    payload = decode_token(request.refresh_token)
    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    access_token = create_access_token(user.id)
    new_refresh_token = create_refresh_token(user.id)

    return AuthResponse(
        user=UserResponse.model_validate(user),
        access_token=access_token,
        refresh_token=new_refresh_token,
    )


@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    """Get the currently authenticated user's profile."""
    return UserResponse.model_validate(current_user)
