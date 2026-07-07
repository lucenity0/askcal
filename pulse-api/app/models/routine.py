import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User


class Routine(TimestampMixin, Base):
    """A recurring habit ("Gym", "Read 30 minutes"). Definitions live here;
    the per-day checkmarks stay device-local — they reset daily by design.

    A fresh account starts with zero rows: routines exist only by explicit
    user action, never seeded.
    """

    __tablename__ = "routines"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(300))
    cadence: Mapped[str] = mapped_column(String(40), default="daily")

    user: Mapped["User"] = relationship(back_populates="routines")
