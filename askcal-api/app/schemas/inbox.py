import datetime as dt

from pydantic import Field

from app.schemas.base import CamelModel


class EmailOut(CamelModel):
    id: str  # Gmail message id, per the contract
    track: str | None
    subject: str | None
    sender: str | None = Field(default=None, serialization_alias="from")
    received_at: dt.datetime
    regret_score: int | None  # returned but never displayed as a number in UI
    estimated_minutes: int | None
    # What this mail wants from you: reply | deadline | read | none. Derived
    # server-side from the stored signals so the app and the auto-tasker cannot
    # disagree about what a piece of mail is.
    needs: str
    snippet: str | None


class InboxResponse(CamelModel):
    emails: list[EmailOut]
    total: int
    unhandled: int


class SyncAccepted(CamelModel):
    status: str
    message: str


class HandleRequest(CamelModel):
    # Optional override when the classifier got the track wrong / hasn't run
    track: str | None = None


class SnoozeRequest(CamelModel):
    until: dt.datetime | None = None  # default: tomorrow 08:00 user-local


class SnoozeResponse(CamelModel):
    snoozed_until: dt.datetime
