from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.deps import CurrentUser, DbSession
from app.models import TaskStatus, Track
from app.schemas.tracks import TrackItem, TrackOut, TracksResponse
from app.services.brew_engine import SCORE_THRESHOLDS

router = APIRouter(prefix="/api", tags=["tracks"])

# "urgent" = would land on long_black or above by itself
URGENT_THRESHOLD = SCORE_THRESHOLDS["long_black"]


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
