# Om Sai Ram
# FastAPI application entry point.

import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import engine, Base, SessionLocal
from .models import Chapter
from .routers import auth, groups, assignments, progress, content, group_chat
from .routers import festivals
from .routers import notification_schedule
from .routers import live_darshan
from .services.festival_scraper import refresh_festivals_in_db

logger = logging.getLogger(__name__)

scheduler = BackgroundScheduler()


def _ensure_chapter_index() -> None:
    """Seed one row per adhyaya so assignments have chapters to reference."""
    with SessionLocal() as db:
        if db.query(Chapter.id).first() is not None:
            return
        titles = json.loads((Path(__file__).parent / "data" / "chapter_titles.json").read_text())
        # version=0 keeps the app on its bundled text (it only pulls server content with a higher version).
        db.add_all(
            Chapter(number=int(n), title=t, content="", language="mr", version=0)
            for n, t in titles.items()
        )
        db.commit()
        logger.info("Seeded %d chapter index rows.", len(titles))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown lifecycle. Creates DB tables on startup."""
    if settings.jwt_secret_key == "CHANGE-THIS-IN-PRODUCTION" and not settings.debug:
        raise RuntimeError("JWT_SECRET_KEY is not set (set DEBUG=true to run locally without it).")
    Base.metadata.create_all(bind=engine)
    _ensure_chapter_index()

    scheduler.add_job(
        refresh_festivals_in_db,
        "cron",
        hour=0,
        minute=0,
        id="scrape_festivals",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("Festival scraper scheduled (daily at midnight).")

    # Initial scrape in the background so startup isn't blocked by the network.
    scheduler.add_job(refresh_festivals_in_db, id="scrape_festivals_startup")

    yield

    scheduler.shutdown(wait=False)


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="API for the Om Sai Ram group reading application.",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# CORS middleware — allows the Flutter app to communicate with the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,  # bearer tokens, no cookies
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Register Routers ────────────────────────────────────────────────────────

app.include_router(
    auth.router,
    prefix=f"/api/{settings.api_version}/auth",
    tags=["Authentication"],
)

app.include_router(
    groups.router,
    prefix=f"/api/{settings.api_version}/groups",
    tags=["Groups"],
)

app.include_router(
    assignments.router,
    prefix=f"/api/{settings.api_version}/assignments",
    tags=["Assignments"],
)

app.include_router(
    progress.router,
    prefix=f"/api/{settings.api_version}/progress",
    tags=["Progress"],
)

app.include_router(
    content.router,
    prefix=f"/api/{settings.api_version}/content",
    tags=["Content"],
)

app.include_router(
    group_chat.router,
    prefix=f"/api/{settings.api_version}/groups",
    tags=["Group Chat"],
)

app.include_router(
    festivals.router,
    prefix=f"/api/{settings.api_version}/festivals",
    tags=["Festivals"],
)

app.include_router(
    notification_schedule.router,
    prefix=f"/api/{settings.api_version}/groups",
    tags=["Notification Schedule"],
)

app.include_router(
    live_darshan.router,
    prefix=f"/api/{settings.api_version}/live-darshan",
    tags=["Live Darshan"],
)


# ─── Health Check ─────────────────────────────────────────────────────────────

@app.get("/health", tags=["Health"])
def health_check():
    """Health check endpoint for monitoring."""
    return {"status": "healthy", "app": settings.app_name}
