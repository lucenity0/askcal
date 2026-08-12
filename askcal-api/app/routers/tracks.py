from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import TaskStatus, Track, TrackKey
from app.schemas.base import CamelModel
from app.schemas.tracks import (
    ProfileRequest,
    ProfileResponse,
    TrackItem,
    TrackOut,
    TracksResponse,
    TrackSettingOut,
)
from app.services.brew_engine import SCORE_THRESHOLDS
from app.services.profile import STUDENT_TYPES, WORK_TYPES, profile_track_settings

router = APIRouter(prefix="/api", tags=["tracks"])

# "urgent" = high-consequence by itself (top scoring band)
URGENT_THRESHOLD = SCORE_THRESHOLDS["long_black"]


class TrackToggle(CamelModel):
    active: bool


@router.patch("/tracks/{key}", response_model=TrackSettingOut)
async def set_track_active(
    key: str, body: TrackToggle, user: CurrentUser, db: DbSession
) -> TrackSettingOut:
    """Turn a track on or off.

    Exists because a track being inactive silently blocks auto-tasking for every
    mail filed under it, and until now nothing in the app could turn one on.
    Design ships inactive by default — so design mail scored 97, sat in the
    inbox, and never became a task, with no way to find out why or change it.
    """
    try:
        track_key = TrackKey(key)
    except ValueError:
        raise AskcalError(422, "INVALID_TRACK", f"Unknown track '{key}'")

    track = await db.scalar(
        select(Track).where(Track.user_id == user.id, Track.key == track_key)
    )
    if track is None:
        raise AskcalError(404, "NOT_FOUND", f"No '{key}' track on this account")

    track.active = body.active
    await db.commit()
    return TrackSettingOut(id=track.key.value, weight=track.weight, active=track.active)


@router.get("/tracks", response_model=TracksResponse)
async def get_tracks(user: CurrentUser, db: DbSession) -> TracksResponse:
    tracks = (
        await db.scalars(
            select(Track)
            .where(Track.user_id == user.id, Track.active.is_(True))
            .options(selectinload(Track.tasks))
        )
    ).all()

    out = []
    for track in tracks:
        open_tasks = sorted(
            (t for t in track.tasks if t.status != TaskStatus.done),
            key=lambda t: (t.due_at is None, t.due_at),
        )
        out.append(
            TrackOut(
                id=track.key.value,
                label=track.key.value.upper(),
                task_count=len(open_tasks),
                urgent_count=sum(1 for t in open_tasks if t.regret_score >= URGENT_THRESHOLD),
                items=[
                    TrackItem(
                        id=t.id,
                        title=t.title,
                        status=t.stage,
                        pipeline=t.pipeline.value if t.pipeline else None,
                        due_at=t.due_at,
                    )
                    for t in open_tasks
                ],
            )
        )
    return TracksResponse(tracks=out)


@router.post("/profile", response_model=ProfileResponse)
async def set_profile(
    body: ProfileRequest, user: CurrentUser, db: DbSession
) -> ProfileResponse:
    """Onboarding answers → per-track weight + active flags."""
    if body.student_type not in STUDENT_TYPES:
        raise AskcalError(422, "INVALID_PROFILE", f"Unknown studentType '{body.student_type}'")
    if body.work_type not in WORK_TYPES:
        raise AskcalError(422, "INVALID_PROFILE", f"Unknown workType '{body.work_type}'")

    settings = profile_track_settings(body.student_type, body.work_type)
    tracks = (
        await db.scalars(select(Track).where(Track.user_id == user.id))
    ).all()
    for track in tracks:
        weight, active = settings[track.key]
        track.weight = weight
        track.active = active
    await db.commit()

    return ProfileResponse(
        tracks=[
            TrackSettingOut(id=t.key.value, weight=t.weight, active=t.active)
            for t in sorted(tracks, key=lambda t: t.key.value)
        ]
    )
