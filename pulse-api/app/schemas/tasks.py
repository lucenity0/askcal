import datetime as dt
import uuid
from typing import Literal

from app.schemas.base import CamelModel
from app.schemas.today import TaskOut


class TaskFullOut(TaskOut):
    """TaskOut + lifecycle fields — what the app hydrates its store from."""

    status: str  # pending | done | carried
    pipeline: str | None = None
    scheduled_for: dt.date | None = None


class TasksResponse(CamelModel):
    tasks: list[TaskFullOut]


class TaskCreateRequest(CamelModel):
    title: str
    track: str = "uni"
    estimated_hours: float | None = None
    when: Literal["today", "tomorrow"] = "today"


class TaskPatchRequest(CamelModel):
    status: str  # pending | done | carried


class TaskIdOut(CamelModel):
    id: uuid.UUID