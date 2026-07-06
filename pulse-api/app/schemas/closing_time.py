import datetime as dt
import uuid

from app.schemas.base import CamelModel
from app.schemas.today import TaskOut


class ClosingTimeRequest(CamelModel):
    date: dt.date
    pulled: list[uuid.UUID] = []
    remaining: list[uuid.UUID] = []
    notes: str | None = None


class ClosingTimeResponse(CamelModel):
    tomorrow_brew: str
    carry_forward_count: int
    message: str


class CarryForwardResponse(CamelModel):
    tasks: list[TaskOut]
    count: int
    projected_brew: str
