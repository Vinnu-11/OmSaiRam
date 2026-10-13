# Om Sai Ram
# Festival scraper — fetches upcoming events from sai.org.in/en/festivals.

import logging
import re
from datetime import datetime

import httpx
from bs4 import BeautifulSoup
from sqlalchemy.orm import Session

from ..database import SessionLocal
from ..models import Festival

logger = logging.getLogger(__name__)

FESTIVALS_URL = "https://sai.org.in/en/festivals"


def _parse_date(date_str: str) -> datetime | None:
    """Try to parse a date string like '28.07.2026' or 'July 28, 2026'."""
    for fmt in ("%d.%m.%Y", "%B %d, %Y", "%b %d, %Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(date_str.strip(), fmt)
        except ValueError:
            continue
    return None


def scrape_festivals() -> list[dict]:
    """Scrape festivals from sai.org.in and return structured data."""
    try:
        response = httpx.get(FESTIVALS_URL, timeout=30, follow_redirects=True)
        response.raise_for_status()
    except httpx.HTTPError as e:
        logger.error(f"Failed to fetch festivals page: {e}")
        return []

    soup = BeautifulSoup(response.text, "html.parser")
    events = []

    # Look for table rows with festival data (the site uses tables for schedules)
    tables = soup.find_all("table")
    for table in tables:
        rows = table.find_all("tr")
        for row in rows:
            cells = row.find_all(["td", "th"])
            if len(cells) >= 2:
                date_text = cells[0].get_text(strip=True)
                title_text = cells[1].get_text(strip=True)
                description = cells[2].get_text(strip=True) if len(cells) > 2 else None
                if date_text and title_text and not title_text.lower().startswith("day"):
                    event_date = _parse_date(date_text)
                    events.append({
                        "title": title_text[:255],
                        "date_label": date_text[:100],
                        "event_date": event_date,
                        "description": description,
                    })

    # Also look for structured content in divs/sections
    # The site uses headings followed by details
    headings = soup.find_all(["h2", "h3", "h4", "strong"])
    for heading in headings:
        text = heading.get_text(strip=True)
        # Look for patterns like "Festival Name - Year" or date-containing strings
        date_match = re.search(r"(\d{1,2}[./]\d{1,2}[./]\d{4})", text)
        if date_match:
            date_str = date_match.group(1)
            title = text.replace(date_str, "").strip(" -–—,")
            event_date = _parse_date(date_str)
            # Get sibling/next paragraph for description
            desc_el = heading.find_next(["p", "div", "span"])
            description = desc_el.get_text(strip=True) if desc_el else None
            if title:
                events.append({
                    "title": title[:255],
                    "date_label": date_str,
                    "event_date": event_date,
                    "description": description,
                })

    # If no structured data found, try parsing the whole page for known festivals
    if not events:
        page_text = soup.get_text()
        # Extract festival names that we know about
        known_festivals = [
            "Ramnavami", "Guru Purnima", "Guru Pournima", "Vijayadashami",
            "Dussehra", "Diwali", "Makar Sankranti",
        ]
        for festival in known_festivals:
            if festival.lower() in page_text.lower():
                # Try to find associated dates nearby
                pattern = rf"({festival}[^.]*?(\d{{1,2}}[./]\d{{1,2}}[./]\d{{4}}))"
                match = re.search(pattern, page_text, re.IGNORECASE)
                if match:
                    date_str = match.group(2)
                    events.append({
                        "title": festival,
                        "date_label": date_str,
                        "event_date": _parse_date(date_str),
                        "description": None,
                    })

        # Fallback: extract the specific festival info visible on the page
        # Based on what we know — Guru Pournima 2026 is July 28-30
        date_patterns = re.findall(
            r"(\d{1,2}[./]\d{1,2}[./]\d{4})", page_text
        )
        if date_patterns and not events:
            # Find surrounding context for each date
            for date_str in date_patterns:
                idx = page_text.find(date_str)
                context = page_text[max(0, idx - 80):idx + len(date_str) + 80]
                lines = [l.strip() for l in context.split("\n") if l.strip()]
                title = next((l for l in lines if date_str not in l and len(l) > 3), "Festival")
                events.append({
                    "title": title[:255],
                    "date_label": date_str,
                    "event_date": _parse_date(date_str),
                    "description": None,
                })

    # Deduplicate by title + date_label
    seen = set()
    unique_events = []
    for e in events:
        key = (e["title"], e["date_label"])
        if key not in seen:
            seen.add(key)
            unique_events.append(e)

    return unique_events


def refresh_festivals_in_db(db: Session | None = None) -> int:
    """Scrape festivals and upsert into the database. Returns count of events stored."""
    own_session = db is None
    if own_session:
        db = SessionLocal()

    try:
        events = scrape_festivals()
        if not events:
            logger.info("No festivals scraped — keeping existing data.")
            return 0

        # Clear old scraped festivals and insert fresh data
        db.query(Festival).delete()

        now = datetime.utcnow()
        for event in events:
            festival = Festival(
                title=event["title"],
                date_label=event["date_label"],
                event_date=event["event_date"],
                description=event.get("description"),
                source_url=FESTIVALS_URL,
                scraped_at=now,
            )
            db.add(festival)

        db.commit()
        logger.info(f"Stored {len(events)} festivals from sai.org.in.")
        return len(events)
    except Exception as e:
        db.rollback()
        logger.error(f"Error refreshing festivals: {e}")
        return 0
    finally:
        if own_session:
            db.close()
