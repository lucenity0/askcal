import logging
from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.deps import CurrentUser, DbSession
from app.models import Task, TaskStatus
from app.schemas.today import PlanSlot, TaskOut, TodayResponse
from app.services.accounts import calendar_token
from app.routers.tasks import due_by_today
from app.services.gcal import busy_blocks
from app.services.scheduling import build_day_plan, humanize_due, user_today

logger = logging.getLogger("askcal.today")

router = APIRouter(prefix="/api", tags=["today"])


@router.get("/today", response_model=TodayResponse)
async def get_today(user: CurrentUser, db: DbSession) -> TodayResponse:
    today = user_today(user.timezone)
    tasks = (
        await db.scalars(
            select(Task)
            .where(
                Task.user_id == user.id,
                Task.status != TaskStatus.done,
                due_by_today(today),
            )
            .options(selectinload(Task.track))
            .order_by(Task.regret_score.desc())
        )
    ).all()

    carry_forward = sum(1 for t in tasks if t.status == TaskStatus.carried)

    # calendar busy blocks are hard no-go zones for the scheduler;
    # no calendar (or a fetch failure) degrades to an open day, never a 500
    busy: list = []
    if token := calendar_token(user):
        try:
            busy = await busy_blocks(token, today, user.timezone)
        except Exception:
            logger.warning("calendar fetch failed; planning without busy blocks",
                           exc_info=True)

    plan, unscheduled = build_day_plan(
        list(tasks), busy, today, user.timezone,
        now=datetime.now(timezone.utc),
    )

    def task_out(t: Task) -> TaskOut:
        return TaskOut(
            id=t.id,
            track=t.track.slug,
            title=t.title,
            meta=humanize_due(t.due_at),
            regret_score=t.regret_score,
            estimated_hours=t.estimated_hours,
        )

    return TodayResponse(
        top_tasks=[task_out(t) for t in tasks[:3]],
        day_plan=[PlanSlot(**slot) for slot in plan],
        unscheduled=[task_out(t) for t in unscheduled],
        carry_forward=carry_forward,
        date=today,
    )
