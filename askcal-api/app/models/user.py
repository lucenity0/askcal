import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import DateTime, Float, String, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.day_note import DayNote
    from app.models.email import Email
    from app.models.mail_account import MailAccount
    from app.models.refresh_token import RefreshToken
    from app.models.routine import Routine
    from app.models.task import Task
    from app.models.track import Track


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(320), unique=True)
    name: Mapped[str | None] = mapped_column(String(200))
    google_sub: Mapped[str | None] = mapped_column(String(64), unique=True)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    # When mail last actually arrived.
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # When a pass last ran, and what went wrong if anything. Separate from the
    # line above because "the sync is not running" and "the sync ran and could
    # not reach your mailbox" are different problems with different fixes, and
    # one timestamp could not tell them apart.
    last_sync_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_sync_error: Mapped[str | None] = mapped_column(Text)
    # Profile setting from the spec ("carry-forward sensitivity"). Stored and
    # never read: nothing has consulted it since the scoring it was meant to
    # feed was removed.
    carry_forward_sensitivity: Mapped[float] = mapped_column(Float, default=1.0)

    # Small, changeable knobs the settings screen writes. JSONB because these
    # keep changing shape; anything that grows a query against it earns a real
    # column at that point.
    preferences: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )

    tracks: Mapped[list["Track"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    tasks: Mapped[list["Task"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    emails: Mapped[list["Email"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    routines: Mapped[list["Routine"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    mail_accounts: Mapped[list["MailAccount"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", lazy="selectin"
    )
    day_notes: Mapped[list["DayNote"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
