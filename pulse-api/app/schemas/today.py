import datetime as dt
import uuid

from app.schemas.base import CamelModel


class BrewData(CamelModel):
    name: str
    tagline: str
    level: str


class TaskOut(CamelModel):
    id: uuid.UUID
    track: str | None
    title: str
    meta: str | None
    regret_score: int
    estimated_hours: float | None


class PlanSlot(CamelModel):
    time: str  # "09:00"
    task_id: uuid.UUID
    duration: int  # minutes


class TodayResponse(CamelModel):
    brew: str
    brew_data: BrewData
    top_tasks: list[TaskOut]
    day_plan: list[PlanSlot]
    carry_forward: int
    date: dt.date
