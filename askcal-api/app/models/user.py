import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import DateTime, Float, String, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.email import Email
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
    # Google's OAuth refresh token, used by the Gmail ingestion layer.
    # TODO: encrypt at rest before production; move to a gmail_accounts table
    # when multi-account (uni + work inbox) lands.
    google_refresh_token: Mapped[str | None] = mapped_column(Text)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Profile setting from the spec ("carry-forward sensitivity"). Not yet
    # wired into the brew engine — the JS source of truth uses a fixed penalty.
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
