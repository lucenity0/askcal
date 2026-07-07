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
from app.routers.tasks import due_by_today
from app.schemas.today import TaskOut
from app.services.scheduling import humanize_due, user_today

router = APIRouter(prefix="/api", tags=["closing-time"])


async def _open_state(
    user_id, db: DbSession, today
) -> tuple[list[Task], list[Task]]:
    """(open tasks for today or earlier by regret desc, the carried subset).
    Tomorrow's tasks aren't part of tonight's ritual."""
    open_tasks = (
        await db.scalars(
            select(Task)
            .where(
                Task.user_id == user_id,
                Task.status != TaskStatus.done,
                due_by_today(today),
            )
            .options(selectinload(Task.track))
            .order_by(Task.regret_score.desc())
        )
    ).all()
    carried = [t for t in open_tasks if t.status == TaskStatus.carried]
    return list(open_tasks), carried


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

    _, carried = await _open_state(user.id, db, user_today(user.timezone))

    log = await db.scalar(
        select(DayLog).where(DayLog.user_id == user.id, DayLog.date == body.date)
    )
    if log is None:
        log = DayLog(user_id=user.id, date=body.date)
        db.add(log)
    log.notes = body.notes
    log.pulled_count = len(body.pulled)
    log.remaining_count = len(body.remaining)

    await db.commit()

    return ClosingTimeResponse(
        carry_forward_count=len(carried),
        message="tomorrow's pre-order updated",
    )


@router.get("/carry-forward", response_model=CarryForwardResponse)
async def carry_forward(user: CurrentUser, db: DbSession) -> CarryForwardResponse:
    today = user_today(user.timezone)
    _, carried = await _open_state(user.id, db, today)
    return CarryForwardResponse(
        tasks=[
            TaskOut(
                id=t.id,
                track=t.track.key.value,
                title=t.title,
                meta=humanize_due(t.due_at),
                regret_score=t.regret_score,
                estimated_hours=t.estimated_hours,
            )
            for t in carried
        ],
        count=len(carried),
    )
