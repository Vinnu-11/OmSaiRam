# Om Sai Ram
# Application configuration — loads settings from environment variables.

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables.

    All sensitive values (database URL, JWT secret) must be set via environment
    variables or a .env file. Never hardcode secrets in source code.
    """

    # Application
    app_name: str = "Om Sai Ram API"
    debug: bool = False
    api_version: str = "v1"

    # Database
    database_url: str = "postgresql://omsairam:omsairam@localhost:5432/omsairam"

    # JWT Authentication
    jwt_secret_key: str = "CHANGE-THIS-IN-PRODUCTION"  # Override via env var
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    # CORS
    cors_origins: list[str] = ["*"]

    # Google OAuth
    google_client_id: str = ""

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


# Singleton settings instance
settings = Settings()
