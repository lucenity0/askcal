from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.deps import CurrentUser, DbSession
from app.models import Task, TaskStatus
from app.schemas.today import BrewData, PlanSlot, TaskOut, TodayResponse
from app.services.brew_engine import BREWS, calculate_brew
from app.services.scheduling import humanize_due, naive_day_plan, user_today

router = APIRouter(prefix="/api", tags=["today"])


@router.get("/today", response_model=TodayResponse)
async def get_today(user: CurrentUser, db: DbSession) -> TodayResponse:
    tasks = (
        await db.scalars(
            select(Task)
            .where(Task.user_id == user.id, Task.status != TaskStatus.done)
            .options(selectinload(Task.track))
            .order_by(Task.regret_score.desc())
        )
    ).all()

    carry_forward = sum(1 for t in tasks if t.status == TaskStatus.carried)
    brew_key = calculate_brew([t.regret_score for t in tasks], carry_forward)
    brew = BREWS[brew_key]
    today = user_today(user.timezone)

    return TodayResponse(
        brew=brew_key,
        brew_data=BrewData(name=brew.name, tagline=brew.tagline, level=brew.level),
        top_tasks=[
            TaskOut(
                id=t.id,
                track=t.track.key.value,
                title=t.title,
                meta=humanize_due(t.due_at, today),
                regret_score=t.regret_score,
                estimated_hours=t.estimated_hours,
            )
            for t in tasks[:3]
        ],
        day_plan=[PlanSlot(**slot) for slot in naive_day_plan(list(tasks))],
        carry_forward=carry_forward,
        date=today,
    )
