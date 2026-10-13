# Om Sai Ram
# Festivals router — serves upcoming events from the cached scrape data.

from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..database import get_db
from ..middleware.auth import get_current_user
from ..models import Festival, User
from ..services.festival_scraper import refresh_festivals_in_db

router = APIRouter()


class FestivalResponse(BaseModel):
    id: str
    title: str
    date_label: str
    event_date: datetime | None
    description: str | None
    source_url: str
    scraped_at: datetime

    class Config:
        from_attributes = True


@router.get("", response_model=list[FestivalResponse])
def get_festivals(db: Session = Depends(get_db)):
    """Get all upcoming festivals/events.

    Returns cached festivals from the database (scraped daily from sai.org.in).
    No authentication required — public endpoint.
    """
    festivals = (
        db.query(Festival)
        .order_by(Festival.event_date.asc().nullslast())
        .all()
    )

    # If no festivals in DB yet, trigger an initial scrape
    if not festivals:
        refresh_festivals_in_db(db)
        festivals = (
            db.query(Festival)
            .order_by(Festival.event_date.asc().nullslast())
            .all()
        )

    return [FestivalResponse.model_validate(f) for f in festivals]


@router.post("/refresh")
def refresh_festivals(db: Session = Depends(get_db), _user: User = Depends(get_current_user)):
    """Force a re-scrape of festivals from sai.org.in.

    Admin/internal endpoint to manually trigger an update.
    """
    count = refresh_festivals_in_db(db)
    return {"status": "ok", "festivals_updated": count}
