import uuid
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.task import Task
    from app.models.user import User


class Track(TimestampMixin, Base):
    __tablename__ = "tracks"
    __table_args__ = (UniqueConstraint("user_id", "slug", name="uq_tracks_user_slug"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # What identifies a track. Stable across renames, unique per user.
    slug: Mapped[str] = mapped_column(String(40))
    # What the user typed. Free to change without moving any mail.
    label: Mapped[str] = mapped_column(String(80))
    # Goes into the classifier prompt verbatim. "work" alone tells the model
    # nothing; "anything from my team or about a PR" is what makes the track
    # do its job.
    description: Mapped[str | None] = mapped_column(Text)
    is_builtin: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    # Whether mail in this track may become a task on its own. Replaces the
    # hardcoded AUTO_TASK_TRACKS set, which could not survive tracks the user
    # invents.
    auto_tasks: Mapped[bool] = mapped_column(Boolean, default=True)
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    active: Mapped[bool] = mapped_column(Boolean, default=True)

    user: Mapped["User"] = relationship(back_populates="tracks")
    tasks: Mapped[list["Task"]] = relationship(back_populates="track")
