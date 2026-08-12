import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.track import Track
    from app.models.user import User


class MailAccount(TimestampMixin, Base):
    """One connected mailbox.

    `users.google_refresh_token` held exactly one, so college mail and personal
    mail could not both reach Askcal — and they want completely different
    treatment, which is why tracks had to become the user's before this could
    mean anything.
    """

    __tablename__ = "mail_accounts"
    __table_args__ = (UniqueConstraint("user_id", "email", name="uq_mail_accounts_user_email"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    email: Mapped[str] = mapped_column(String(320))
    google_sub: Mapped[str | None] = mapped_column(String(64))
    # TODO: encrypt at rest (#19). Moving it here changed where it lives, not
    # how it is stored, and it is still the most sensitive column in the schema.
    google_refresh_token: Mapped[str | None] = mapped_column(Text)

    # What mail at this address usually is. Passed to the classifier as a
    # leaning, never as a rule — a bill arriving at a college address is still
    # a bill, and an account that forced its track would file it wrong every
    # time with nothing on screen explaining why.
    default_track_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tracks.id", ondelete="SET NULL")
    )

    # The account that owns the sign-in and the calendar. Exactly one per user,
    # enforced by a partial unique index.
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    # Pause an inbox without unlinking it — "not this term" is a different
    # thing from "forget this address", and only one of them should lose the
    # token.
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="mail_accounts")
    default_track: Mapped["Track | None"] = relationship(lazy="selectin")
