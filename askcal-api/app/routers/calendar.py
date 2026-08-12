import datetime as dt

from fastapi import APIRouter

from app.core.errors import AskcalError
from app.deps import CurrentUser
from app.schemas.calendar import CalendarEventOut, CalendarResponse
from app.services.accounts import calendar_token
from app.services.gcal import fetch_events
from app.services.scheduling import user_today

router = APIRouter(prefix="/api", tags=["calendar"])


@router.get("/calendar", response_model=CalendarResponse)
async def get_calendar(
    user: CurrentUser,
    start: dt.date | None = None,
    end: dt.date | None = None,
) -> CalendarResponse:
    """Read-only events from the user's primary Google calendar.
    Defaults to today; `end` defaults to `start`."""
    token = calendar_token(user)
    if not token:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "No Google connection for this account")

    start = start or user_today(user.timezone)
    end = end or start
    if end < start:
        raise AskcalError(422, "INVALID_RANGE", "end is before start")

    events = await fetch_events(token, start, end, user.timezone)
    return CalendarResponse(
        events=[
            CalendarEventOut(
                id=e.id, title=e.title, start=e.start, end=e.end, all_day=e.all_day
            )
            for e in events
        ]
    )