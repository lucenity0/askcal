import datetime as dt

from app.schemas.base import CamelModel


class CalendarEventOut(CamelModel):
    """Mirrors the frontend's CalendarEvent model (title/start/end/source);
    start/end are ISO 8601 datetimes (null for all-day events)."""

    id: str
    title: str
    start: dt.datetime | None
    end: dt.datetime | None
    all_day: bool
    source: str = "google"


class CalendarResponse(CamelModel):
    events: list[CalendarEventOut]