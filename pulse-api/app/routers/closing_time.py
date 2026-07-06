from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import select, update
from sqlalchemy.orm import selectinload

from app.deps import CurrentUser, DbSession
from app.models import DayLog, Task, TaskStatus
from app.schemas.closing_time import (
    CarryForwardResponse,
    ClosingTimeRequest,
    ClosingTimeResponse,
)
from app.schemas.today import TaskOut
from app.services.brew_engine import calculate_brew
from app.services.scheduling import humanize_due, user_today

router = APIRouter(prefix="/api", tags=["closing-time"])


async def _projected_brew(user_id, db: DbSession) -> tuple[str, int, list[Task]]:
    """Brew tomorrow opens with, given every still-open task."""
    open_tasks = (
        await db.scalars(
            select(Task)
            .where(Task.user_id == user_id, Task.status != TaskStatus.done)
            .options(selectinload(Task.track))
            .order_by(Task.regret_score.desc())
        )
    ).all()
    carried = [t for t in open_tasks if t.status == TaskStatus.carried]
    brew = calculate_brew([t.regret_score for t in open_tasks], len(carried))
    return brew, len(carried), list(open_tasks)


@router.post("/closing-time", response_model=ClosingTimeResponse)
async def closing_time(
    body: ClosingTimeRequest, user: CurrentUser, db: DbSession
) -> ClosingTimeResponse:
    now = datetime.now(timezone.utc)

    if body.pulled:
        await db.execute(
            update(Task)
            .where(Task.user_id == user.id, Task.id.in_(body.pulled))
            .values(status=TaskStatus.done, completed_at=now)
        )
    if body.remaining:
        await db.execute(
            update(Task)
            .where(Task.user_id == user.id, Task.id.in_(body.remaining))
            .values(status=TaskStatus.carried, carried_count=Task.carried_count + 1)
        )

    tomorrow_brew, carry_count, _ = await _projected_brew(user.id, db)

    log = await db.scalar(
        select(DayLog).where(DayLog.user_id == user.id, DayLog.date == body.date)
    )
    if log is None:
        log = DayLog(user_id=user.id, date=body.date)
        db.add(log)
    log.notes = body.notes
    log.pulled_count = len(body.pulled)
    log.remaining_count = len(body.remaining)
    log.projected_brew = tomorrow_brew

    await db.commit()

    return ClosingTimeResponse(
        tomorrow_brew=tomorrow_brew,
        carry_forward_count=carry_count,
        message="tomorrow's pre-order updated",
    )


@router.get("/carry-forward", response_model=CarryForwardResponse)
async def carry_forward(user: CurrentUser, db: DbSession) -> CarryForwardResponse:
    projected, carry_count, open_tasks = await _projected_brew(user.id, db)
    today = user_today(user.timezone)
    carried = [t for t in open_tasks if t.status == TaskStatus.carried]
    return CarryForwardResponse(
        tasks=[
            TaskOut(
                id=t.id,
                track=t.track.key.value,
                title=t.title,
                meta=humanize_due(t.due_at, today),
                regret_score=t.regret_score,
                estimated_hours=t.estimated_hours,
            )
            for t in carried
        ],
        count=carry_count,
        projected_brew=projected,
    )
