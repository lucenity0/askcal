import datetime as dt
import uuid

from app.schemas.base import CamelModel


class TrackItem(CamelModel):
    id: uuid.UUID
    title: str
    status: str | None  # track-specific stage, e.g. "oa_open"
    pipeline: str | None  # career only: applied | oa | interview | offer | reject
    due_at: dt.datetime | None


class TrackOut(CamelModel):
    id: str  # track key: career | design | uni | feed
    label: str
    task_count: int
    urgent_count: int
    items: list[TrackItem]


class TracksResponse(CamelModel):
    tracks: list[TrackOut]


class ProfileRequest(CamelModel):
    student_type: str  # student | working | both
    work_type: str     # design | dev | both | other | none


class TrackSettingOut(CamelModel):
    id: str
    weight: float
    active: bool


class ProfileResponse(CamelModel):
    tracks: list[TrackSettingOut]
