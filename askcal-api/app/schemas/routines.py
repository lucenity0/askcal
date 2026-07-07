import uuid

from pydantic import Field

from app.schemas.base import CamelModel


class RoutineOut(CamelModel):
    id: uuid.UUID
    title: str
    cadence: str


class RoutinesResponse(CamelModel):
    routines: list[RoutineOut]


class RoutineCreateRequest(CamelModel):
    title: str = Field(min_length=1, max_length=300)
    cadence: str = Field(default="daily", max_length=40)
