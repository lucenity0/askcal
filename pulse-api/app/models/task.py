import enum
import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Date, DateTime, Enum, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.base import TimestampMixin

if TYPE_CHECKING:
    from app.models.email import Email
    from app.models.track import Track
    from app.models.user import User


class TaskStatus(enum.StrEnum):
    pending = "pending"
    done = "done"  # "shot pulled" at closing time
    carried = "carried"  # unfinished yesterday, feeds the carry-forward penalty


class CareerPipeline(enum.StrEnum):
    applied = "applied"
    oa = "oa"
    interview = "interview"
    offer = "offer"
    reject = "reject"


class Task(TimestampMixin, Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    track_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tracks.id", ondelete="CASCADE"), index=True
    )
    source_email_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("emails.id", ondelete="SET NULL")
    )
    title: Mapped[str] = mapped_column(String(500))
    # Track-specific display state, e.g. "oa_open" for career items
    stage: Mapped[str | None] = mapped_column(String(50))
    pipeline: Mapped[CareerPipeline | None] = mapped_column(
        Enum(CareerPipeline, name="career_pipeline")
    )
    regret_score: Mapped[int] = mapped_column(Integer, default=0)
    estimated_hours: Mapped[float | None] = mapped_column(Float)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # The day this task belongs to. NULL means today (legacy rows / no
    # explicit choice); Today/plan/review endpoints exclude future days.
    scheduled_for: Mapped[date | None] = mapped_column(Date)
    status: Mapped[TaskStatus] = mapped_column(
        Enum(TaskStatus, name="task_status"), default=TaskStatus.pending
    )
    carried_count: Mapped[int] = mapped_column(Integer, default=0)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="tasks")
    track: Mapped["Track"] = relationship(back_populates="tasks")
    source_email: Mapped["Email | None"] = relationship(back_populates="tasks")
