import datetime as dt
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User


class DayNote(TimestampMixin, Base):
    """Whatever the day needed writing down that was not a task.

    Askcal could only hold things with a shape — a task, a mail, a track — so a
    thought about the day had nowhere to go, which is a strange gap in an app
    built to look like a notebook.
    """

    __tablename__ = "day_notes"
    __table_args__ = (UniqueConstraint("user_id", "day", name="uq_day_notes_user_day"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # The user's local day. A plain date, not a timestamp: the note belongs to
    # the page headed "August 12", and putting that through a timezone would
    # move it to a different page for the same person.
    day: Mapped[dt.date] = mapped_column(Date)
    body: Mapped[str] = mapped_column(Text, default="", server_default="")

    user: Mapped["User"] = relationship(back_populates="day_notes")
