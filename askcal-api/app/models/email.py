import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin
from app.models.track import TrackKey

if TYPE_CHECKING:
    from app.models.task import Task
    from app.models.track import Track
    from app.models.user import User


class Email(TimestampMixin, Base):
    """Raw ingested Gmail message + async classifier output.

    Per the API contracts: store raw emails, run the classifier async —
    regret_score / track / estimated_minutes stay NULL until classified_at
    is set.
    """

    __tablename__ = "emails"
    __table_args__ = (UniqueConstraint("user_id", "gmail_id"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    gmail_id: Mapped[str] = mapped_column(String(64))
    thread_id: Mapped[str | None] = mapped_column(String(64), index=True)
    # Which connected mailbox this came from (uni vs work account)
    account_email: Mapped[str | None] = mapped_column(String(320))
    subject: Mapped[str | None] = mapped_column(Text)
    sender: Mapped[str | None] = mapped_column(String(320))
    snippet: Mapped[str | None] = mapped_column(Text)
    # Extracted plain-text body (truncated) — classifier input + future ML corpus
    body_text: Mapped[str | None] = mapped_column(Text)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    raw: Mapped[dict[str, Any] | None] = mapped_column(JSONB)

    # Classifier output (async — track/consequence signals + regret scoring)
    # `track` is the old enum column, still written so a rollback has its data.
    # `track_id` is the one to read: it points at a row the user can rename.
    track: Mapped[TrackKey | None] = mapped_column(Enum(TrackKey, name="track_key"))
    track_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tracks.id", ondelete="SET NULL"), index=True
    )
    regret_score: Mapped[int | None] = mapped_column(Integer)
    estimated_minutes: Mapped[int | None] = mapped_column(Integer)
    # Raw signals the model extracted (EmailSignals dump) — audit trail for the
    # regret formula and training data for the future ML scoring model
    signals: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    classified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Failed classification attempts. Past classify_max_attempts the email stops
    # being picked up: a message the model can never parse would otherwise be
    # re-sent every sync interval forever, crowding the pass limit and burning
    # quota indefinitely.
    classify_attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0", default=0
    )

    # Triage state: swipe right → handled, swipe left → snoozed
    handled: Mapped[bool] = mapped_column(Boolean, default=False)
    snoozed_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="emails")
    tasks: Mapped[list["Task"]] = relationship(back_populates="source_email")
    # selectin so reading the track's name off a list of emails is one extra
    # query rather than one per email — and so it works at all under async,
    # where a lazy load outside the session raises.
    track_ref: Mapped["Track | None"] = relationship(lazy="selectin")
