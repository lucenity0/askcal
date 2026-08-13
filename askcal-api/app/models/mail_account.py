import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    String,
    Table,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin
from app.models.types import EncryptedText

# Which tracks a mailbox usually carries. A plain association table: the pair
# is the whole fact, and there is nothing else to say about it.
mail_account_tracks = Table(
    "mail_account_tracks",
    Base.metadata,
    Column(
        "account_id",
        UUID(as_uuid=True),
        ForeignKey("mail_accounts.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "track_id",
        UUID(as_uuid=True),
        ForeignKey("tracks.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)

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
    # What the user calls this mailbox — "college", "work". The address itself
    # is not something they need read back to them, and it makes a poor title:
    # it is long, it wraps, and they already know it.
    label: Mapped[str | None] = mapped_column(String(80))
    google_sub: Mapped[str | None] = mapped_column(String(64))
    # Encrypted at rest — see app/models/types.py. A refresh token is a
    # long-lived key to somebody's whole mailbox and calendar, and this is the
    # most sensitive column in the schema.
    google_refresh_token: Mapped[str | None] = mapped_column(EncryptedText)

    # Superseded by `tracks` below. Kept one release; nothing reads it.
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

    # What mail at this address is usually about — as many as apply. No address
    # is one thing: a college account carries coursework, fees and the odd
    # recruiter, and being forced to pick the closest single one is the same
    # mistake the five hardcoded tracks made.
    #
    # Passed to the classifier as a leaning, never a rule. An account that
    # forced its tracks would file a bill arriving at a college address as
    # coursework every time, with nothing on screen explaining why.
    tracks: Mapped[list["Track"]] = relationship(
        secondary="mail_account_tracks", lazy="selectin"
    )
