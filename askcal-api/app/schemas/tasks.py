import datetime as dt
import uuid

from app.schemas.base import CamelModel
from app.schemas.today import TaskOut


class TaskFullOut(TaskOut):
    """TaskOut + lifecycle fields — what the app hydrates its store from."""

    status: str  # pending | done | carried
    pipeline: str | None = None
    scheduled_for: dt.date | None = None
    scheduled_at: dt.datetime | None = None   # pinned start time, if any
    due_at: dt.datetime | None = None         # raw deadline for client countdown


class TasksResponse(CamelModel):
    tasks: list[TaskFullOut]


class TaskCreateRequest(CamelModel):
    title: str
    track: str = "uni"
    estimated_hours: float | None = None
    # The day this task lives on (defaults to today when omitted).
    scheduled_for: dt.date | None = None
    # Optional pinned start time — when present the planner fixes the task
    # here instead of auto-placing it.
    scheduled_at: dt.datetime | None = None
    # Optional deadline.
    due_at: dt.datetime | None = None


class TaskPatchRequest(CamelModel):
    """All fields optional — a patch changes only what it carries. `unset`
    sentinels distinguish 'clear this' from 'leave untouched' for the nullable
    scheduling fields."""

    status: str | None = None                 # pending | done | carried
    scheduled_for: dt.date | None = None
    scheduled_at: dt.datetime | None = None
    due_at: dt.datetime | None = None


class TaskIdOut(CamelModel):
    id: uuid.UUID