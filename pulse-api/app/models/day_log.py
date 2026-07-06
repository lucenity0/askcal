import datetime as dt
import uuid

from sqlalchemy import Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.models.base import TimestampMixin


class DayLog(TimestampMixin, Base):
    """One row per closing-time ritual — feeds tomorrow's brew and history."""

    __tablename__ = "day_logs"
    __table_args__ = (UniqueConstraint("user_id", "date"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[dt.date] = mapped_column(Date)
    notes: Mapped[str | None] = mapped_column(Text)
    pulled_count: Mapped[int] = mapped_column(Integer, default=0)
    remaining_count: Mapped[int] = mapped_column(Integer, default=0)
    # Brew key projected for the following day at closing time
    projected_brew: Mapped[str | None] = mapped_column(String(20))
