# Om Sai Ram
# Live Darshan stream URL proxy — extracts the HLS m3u8 URL from sai.org.in

import re
import logging

import httpx
from fastapi import APIRouter, HTTPException

logger = logging.getLogger(__name__)

router = APIRouter()

_SAI_PAGE_URL = "https://sai.org.in/node/504?width=960&height=540&iframe=true"
# The URL in Drupal settings JSON uses escaped slashes: https:\/\/...
_STREAM_URL_PATTERN = re.compile(
    r'"newurl"\s*:\s*"(https?:[^"]+\.m3u8[^"]*)"'
)


@router.get("/stream-url")
async def get_stream_url():
    """Fetch the sai.org.in live darshan page and extract the HLS stream URL.

    The stream URL contains expiry tokens that rotate every few hours,
    so this endpoint fetches a fresh one each time.
    """
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(_SAI_PAGE_URL)
            resp.raise_for_status()
    except httpx.HTTPError as e:
        logger.warning(f"Failed to fetch sai.org.in: {e}")
        raise HTTPException(
            status_code=502,
            detail="Could not reach sai.org.in to retrieve stream URL.",
        )

    # Extract the m3u8 URL from the Drupal settings JSON embedded in the page
    match = _STREAM_URL_PATTERN.search(resp.text)
    if not match:
        logger.warning("Could not find stream URL in sai.org.in page")
        raise HTTPException(
            status_code=502,
            detail="Live stream URL not found — stream may be offline.",
        )

    # The URL may have unicode escapes (\u0026 for &) and escaped slashes (\/)
    stream_url = match.group(1).replace("\\/", "/")
    stream_url = stream_url.encode().decode("unicode_escape")
    return {"url": stream_url}
