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
    id: str  # the slug — stable across renames
    label: str  # what the user called it
    description: str | None  # their words for what belongs here; steers the classifier
    active: bool
    auto_tasks: bool
    is_builtin: bool  # built-ins can be renamed and turned off, but not deleted
    weight: float
    task_count: int
    urgent_count: int
    items: list[TrackItem]


class TracksResponse(CamelModel):
    tracks: list[TrackOut]


class TrackCreateRequest(CamelModel):
    label: str
    description: str | None = None
    active: bool = True
    auto_tasks: bool = True


class TrackPatchRequest(CamelModel):
    """Every field optional — only what the client actually sent is applied.

    The slug never moves. Renaming a track must not restate where its mail
    belongs, and the stored signals on every already-classified email point at
    the slug.
    """

    label: str | None = None
    description: str | None = None
    active: bool | None = None
    auto_tasks: bool | None = None
    weight: float | None = None


class ProfileRequest(CamelModel):
    student_type: str  # student | working | both
    work_type: str     # design | dev | both | other | none


class TrackSettingOut(CamelModel):
    id: str
    weight: float
    active: bool


class ProfileResponse(CamelModel):
    tracks: list[TrackSettingOut]
