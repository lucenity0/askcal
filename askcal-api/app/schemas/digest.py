import datetime as dt

from app.schemas.base import CamelModel


class DigestResponse(CamelModel):
    """One shape for both digests.

    Shared deliberately: the morning and evening summaries answer the same
    question at different ends of the day, and two schemas would drift into
    two screens.
    """

    date: dt.date
    # The one line worth putting in a notification.
    headline: str
    # Supporting detail, already phrased — the client renders these verbatim
    # rather than re-deriving copy from counts and getting it subtly different.
    lines: list[str] = []

    # Morning
    task_count: int = 0
    due_today: int = 0
    carried_over: int = 0
    first_slot: str | None = None
    planned_minutes: int = 0
    needs_reply: int = 0
    mail_with_deadlines: int = 0

    # Evening
    done: int = 0
    carried: int = 0
    still_open: int = 0
    streak: int = 0
