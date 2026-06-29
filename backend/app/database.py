# Om Sai Ram
# Database connection setup using SQLAlchemy.

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

from .config import settings


# Create the SQLAlchemy engine
# Use pool settings only for PostgreSQL (not SQLite)
_engine_kwargs = {"pool_pre_ping": True}
if settings.database_url.startswith("postgresql"):
    _engine_kwargs.update({"pool_size": 10, "max_overflow": 20})

engine = create_engine(settings.database_url, **_engine_kwargs)

# Session factory for creating database sessions
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """Base class for all SQLAlchemy models."""
    pass


def get_db():
    """Dependency that provides a database session.

    Yields a session and ensures it's closed after the request.
    Use as a FastAPI dependency: db = Depends(get_db)
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
