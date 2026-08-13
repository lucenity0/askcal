"""Google Calendar, read-only.

Rides the same OAuth refresh token as Gmail (calendar.readonly is part of
the single consent flow in gmail.py). Nothing here ever writes to Google.
"""

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta, tzinfo
from zoneinfo import ZoneInfo

import httpx

from app.core.errors import AskcalError
from app.services.gmail import refresh_google_access_token

logger = logging.getLogger("askcal.gcal")

GCAL_EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"


@dataclass
class GCalEvent:
    id: str
    title: str
    start: datetime | None  # None for all-day events
    end: datetime | None
    all_day: bool
    busy: bool  # transparency != "transparent"


def _parse_when(node: dict) -> tuple[datetime | None, bool]:
    if dt_str := node.get("dateTime"):
        return datetime.fromisoformat(dt_str), False
    return None, True  # date-only → all-day


# /api/today (busy blocks) and /api/calendar (events) both need the same
# Google fetch; a short TTL cache turns the second call into a dict lookup.
_EVENTS_TTL_SECONDS = 90.0
_events_cache: dict[tuple, tuple[float, list[GCalEvent]]] = {}

# Tokens missing the calendar scope fail with 403 on EVERY call — without a
# negative cache each /api/today paid a ~500ms doomed Google round-trip.
_SCOPE_DENIED_TTL_SECONDS = 600.0
_scope_denied: dict[str, float] = {}


async def fetch_events(
    google_refresh_token: str, start: date, end: date, tz_name: str = "UTC"
) -> list[GCalEvent]:
    """Events on the primary calendar in [start, end], recurring expanded.
    Cached ~90s — freshness beyond that isn't worth a Google round-trip
    on every screen load."""
    import time as _time

    denied_at = _scope_denied.get(google_refresh_token)
    if denied_at and _time.time() - denied_at < _SCOPE_DENIED_TTL_SECONDS:
        raise AskcalError(403, "CALENDAR_NOT_AUTHORIZED",
                         "Reconnect Google to grant calendar access")

    cache_key = (google_refresh_token, start.isoformat(), end.isoformat(), tz_name)
    cached = _events_cache.get(cache_key)
    if cached and _time.time() - cached[0] < _EVENTS_TTL_SECONDS:
        return cached[1]

    tz: tzinfo
    try:
        tz = ZoneInfo(tz_name)
    except (KeyError, ValueError):
        tz = UTC

    access_token = await refresh_google_access_token(google_refresh_token)
    time_min = datetime.combine(start, time.min, tzinfo=tz)
    time_max = datetime.combine(end + timedelta(days=1), time.min, tzinfo=tz)

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            GCAL_EVENTS_URL,
            params={
                "timeMin": time_min.isoformat(),
                "timeMax": time_max.isoformat(),
                "singleEvents": "true",
                "orderBy": "startTime",
                "maxResults": 250,
            },
            headers={"Authorization": f"Bearer {access_token}"},
        )
    if resp.status_code == 401:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "Google auth expired")
    if resp.status_code == 403:
        # token predates the calendar scope — user needs to reconnect
        _scope_denied[google_refresh_token] = _time.time()
        raise AskcalError(403, "CALENDAR_NOT_AUTHORIZED",
                         "Reconnect Google to grant calendar access")
    resp.raise_for_status()

    events: list[GCalEvent] = []
    for item in resp.json().get("items", []):
        if item.get("status") == "cancelled":
            continue
        start_dt, all_day = _parse_when(item.get("start", {}))
        end_dt, _ = _parse_when(item.get("end", {}))
        events.append(
            GCalEvent(
                id=item.get("id", ""),
                title=item.get("summary") or "(untitled)",
                start=start_dt,
                end=end_dt,
                all_day=all_day,
                busy=item.get("transparency") != "transparent",
            )
        )
    _events_cache[cache_key] = (_time.time(), events)
    return events


async def busy_blocks(
    google_refresh_token: str, day: date, tz_name: str
) -> list[tuple[datetime, datetime]]:
    """Hard no-go zones for the scheduler. All-day events don't block —
    a birthday shouldn't wipe out the whole working day."""
    events = await fetch_events(google_refresh_token, day, day, tz_name)
    return [
        (e.start, e.end)
        for e in events
        if e.busy and not e.all_day and e.start is not None and e.end is not None
    ]
