# Om Sai Ram
# FastAPI application entry point.

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import engine, Base
from .routers import auth, groups, assignments, progress, content


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown lifecycle. Creates DB tables on startup."""
    Base.metadata.create_all(bind=engine)
    yield


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
    allow_credentials=True,
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


# ─── Health Check ─────────────────────────────────────────────────────────────

@app.get("/health", tags=["Health"])
def health_check():
    """Health check endpoint for monitoring."""
    return {"status": "healthy", "app": settings.app_name}
