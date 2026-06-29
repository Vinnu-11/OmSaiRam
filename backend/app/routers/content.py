# Om Sai Ram
# Content router — serve Satcharita chapters and version info.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Chapter
from ..schemas import ChapterResponse, ContentVersionResponse
from ..middleware.auth import get_current_user

router = APIRouter()


@router.get("/versions", response_model=ContentVersionResponse)
def get_content_version(
    language: str = "en",
    db: Session = Depends(get_db),
):
    """Get the current content version for a language.

    Used by the mobile app to check if content updates are available.
    No authentication required — public endpoint.
    """
    chapters = (
        db.query(Chapter)
        .filter(Chapter.language == language)
        .all()
    )

    if not chapters:
        return ContentVersionResponse(
            language=language,
            version=0,
            total_chapters=0,
        )

    max_version = max(c.version for c in chapters)
    return ContentVersionResponse(
        language=language,
        version=max_version,
        total_chapters=len(chapters),
    )


@router.get("/chapters/{language}", response_model=list[ChapterResponse])
def get_chapters(
    language: str = "en",
    db: Session = Depends(get_db),
):
    """Get all chapters for a given language.

    Returns chapters ordered by number.
    No authentication required — public endpoint.
    """
    chapters = (
        db.query(Chapter)
        .filter(Chapter.language == language)
        .order_by(Chapter.number)
        .all()
    )

    return [ChapterResponse.model_validate(c) for c in chapters]


@router.get("/chapters/{language}/{chapter_number}", response_model=ChapterResponse)
def get_chapter(
    language: str,
    chapter_number: int,
    db: Session = Depends(get_db),
):
    """Get a single chapter by number and language.

    No authentication required — public endpoint.
    """
    chapter = (
        db.query(Chapter)
        .filter(
            Chapter.language == language,
            Chapter.number == chapter_number,
        )
        .first()
    )

    if not chapter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chapter {chapter_number} not found for language '{language}'",
        )

    return ChapterResponse.model_validate(chapter)
