# Om Sai Ram
# Auth router — registration, login, social auth, OTP phone auth, and token refresh.

import logging
import random
import string
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, PhoneOtp
from ..schemas import (
    RegisterRequest,
    LoginRequest,
    PhoneSendOtpRequest,
    PhoneVerifyOtpRequest,
    SocialAuthRequest,
    RefreshRequest,
    UpdateProfileRequest,
    ChangePasswordRequest,
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

logger = logging.getLogger(__name__)

OTP_EXPIRY_MINUTES = 10
OTP_LENGTH = 6

router = APIRouter()


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    """Register a new user with email/password or phone/password.

    At least one of email or phone_number must be provided.
    Returns user data and JWT tokens on success.
    """
    if not request.email and not request.phone_number:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Either email or phone number is required",
        )

    if request.email:
        email = request.email.lower()
        if db.query(User).filter(User.email == email).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    else:
        email = None

    if request.phone_number:
        if db.query(User).filter(User.phone_number == request.phone_number).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Phone number already registered")

    user = User(
        email=email,
        phone_number=request.phone_number,
        name=request.name,
        password_hash=hash_password(request.password),
        auth_provider="email" if email else "phone",
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


@router.post("/phone/send-otp", status_code=status.HTTP_200_OK)
def send_otp(request: PhoneSendOtpRequest, db: Session = Depends(get_db)):
    """Send a one-time password to the given phone number.

    The OTP is 6 digits and expires in 10 minutes.
    In production, integrate an SMS provider (e.g. MSG91, Twilio) here.
    For development, the OTP is logged to the server console.
    """
    phone = request.phone_number

    # Invalidate any previous unused OTPs for this number
    db.query(PhoneOtp).filter(
        PhoneOtp.phone_number == phone,
        PhoneOtp.is_used == False,  # noqa: E712
    ).delete()
    db.commit()

    # Generate a 6-digit OTP
    otp = "".join(random.choices(string.digits, k=OTP_LENGTH))
    expires_at = datetime.utcnow() + timedelta(minutes=OTP_EXPIRY_MINUTES)

    otp_record = PhoneOtp(
        phone_number=phone,
        otp_hash=hash_password(otp),
        expires_at=expires_at,
    )
    db.add(otp_record)
    db.commit()

    # TODO: Replace with real SMS delivery via MSG91 / Twilio
    # msg91_send_otp(phone, otp)
    logger.info("OTP for %s: %s (expires %s)", phone, otp, expires_at)

    return {"detail": f"OTP sent to {phone}", "expires_in_minutes": OTP_EXPIRY_MINUTES}


@router.post("/phone/verify-otp", response_model=AuthResponse)
def verify_otp(request: PhoneVerifyOtpRequest, db: Session = Depends(get_db)):
    """Verify the OTP and return JWT tokens.

    If no account exists for the phone number and a `name` is provided,
    a new account is created automatically (first-time sign-up flow).
    If no account exists and no name is provided, raises 404 so the
    client can ask for the user's name before retrying.
    """
    # Find the latest unused, unexpired OTP for this number
    otp_record = (
        db.query(PhoneOtp)
        .filter(
            PhoneOtp.phone_number == request.phone_number,
            PhoneOtp.is_used == False,  # noqa: E712
            PhoneOtp.expires_at > datetime.utcnow(),
        )
        .order_by(PhoneOtp.created_at.desc())
        .first()
    )

    if not otp_record or not verify_password(request.otp, otp_record.otp_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired OTP. Please request a new one.",
        )

    # Mark OTP as used
    otp_record.is_used = True
    db.commit()

    # Find or create the user
    user = db.query(User).filter(User.phone_number == request.phone_number).first()

    if not user:
        if not request.name:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No account found. Please provide your name to create one.",
            )
        user = User(
            phone_number=request.phone_number,
            name=request.name,
            auth_provider="phone",
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


@router.patch("/me", response_model=UserResponse)
def update_profile(
    request: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update the current user's profile fields."""
    updates = request.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    if "email" in updates and updates["email"]:
        email = updates["email"].lower()
        existing = db.query(User).filter(User.email == email, User.id != current_user.id).first()
        if existing:
            raise HTTPException(status_code=400, detail="Email already in use")
        updates["email"] = email

    if "phone_number" in updates and updates["phone_number"]:
        existing = db.query(User).filter(
            User.phone_number == updates["phone_number"],
            User.id != current_user.id,
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="Phone number already in use")

    for key, value in updates.items():
        setattr(current_user, key, value)
    db.commit()
    db.refresh(current_user)
    return UserResponse.model_validate(current_user)


@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    request: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Change password for email-authenticated users."""
    if current_user.auth_provider != "email":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password change is only available for email accounts",
        )

    if not current_user.password_hash or not verify_password(
        request.current_password, current_user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )

    current_user.password_hash = hash_password(request.new_password)
    db.commit()
    return {"detail": "Password changed successfully"}
