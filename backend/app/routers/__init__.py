# Om Sai Ram
from .auth import router as auth_router
from .groups import router as groups_router
from .assignments import router as assignments_router
from .progress import router as progress_router
from .content import router as content_router

from . import auth, groups, assignments, progress, content

__all__ = ["auth", "groups", "assignments", "progress", "content"]
