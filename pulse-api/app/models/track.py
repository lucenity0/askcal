import enum
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Enum, Float, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.task import Task
    from app.models.user import User


class TrackKey(enum.StrEnum):
    career = "career"
    design = "design"
    uni = "uni"
    feed = "feed"


class Track(TimestampMixin, Base):
    __tablename__ = "tracks"
    __table_args__ = (UniqueConstraint("user_id", "key"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    key: Mapped[TrackKey] = mapped_column(Enum(TrackKey, name="track_key"))
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    active: Mapped[bool] = mapped_column(Boolean, default=True)

    user: Mapped["User"] = relationship(back_populates="tracks")
    tasks: Mapped[list["Task"]] = relationship(back_populates="track")
