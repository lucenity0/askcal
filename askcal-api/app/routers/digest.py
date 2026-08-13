"""The two daily summaries, as endpoints.

Both notifications previously fired with fixed text and opened onto the app's
front page. These give them something to say and somewhere to land — and the
copy in the push comes from the same call as the screen behind it, so the two
cannot disagree.
"""

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.deps import CurrentUser, DbSession
from app.models import Email, Task, TaskStatus
from app.routers.tasks import due_by_today
from app.schemas.digest import DigestResponse
from app.services.accounts import calendar_token
from app.services.digest import evening_digest, morning_digest
from app.services.gcal import busy_blocks
from app.services.scheduling import build_day_plan, user_now, user_today

router = APIRouter(prefix="/api/digest", tags=["digest"])


async def _todays_tasks(db: DbSession, user: CurrentUser, *, include_done: bool):
    today = user_today(user.timezone)
    stmt = (
        select(Task)
        .where(Task.user_id == user.id, due_by_today(today))
        .options(selectinload(Task.track))
        .order_by(Task.regret_score.desc())
    )
    if not include_done:
        stmt = stmt.where(Task.status != TaskStatus.done)
    return list(await db.scalars(stmt))


@router.get("/morning", response_model=DigestResponse)
async def get_morning(user: CurrentUser, db: DbSession) -> DigestResponse:
    """What today asks of you, before you have looked at it."""
    now = user_now(user.timezone)
    tasks = await _todays_tasks(db, user, include_done=False)

    emails = list(
        await db.scalars(
            select(Email).where(Email.user_id == user.id, Email.handled.is_(False))
        )
    )

    # A calendar that will not load degrades to an open day, never a 500 — the
    # digest firing with a slightly optimistic plan beats it not firing at all.
    busy: list = []
    if token := calendar_token(user):
        try:
            busy = await busy_blocks(token, now.date(), user.timezone)
        except Exception:  # noqa: BLE001 — logged upstream; never fails the digest
            busy = []

    plan, _ = build_day_plan(tasks, busy, now.date(), user.timezone, now=now)
    return DigestResponse(**morning_digest(tasks, emails, plan, now))


@router.get("/evening", response_model=DigestResponse)
async def get_evening(user: CurrentUser, db: DbSession) -> DigestResponse:
    """How the day actually went."""
    now = user_now(user.timezone)
    tasks = await _todays_tasks(db, user, include_done=True)
    # The streak is kept on the device, not here — the app fills it in. The
    # server has no day-closure history to count from, and inventing a number
    # for it would be worse than leaving it at zero.
    return DigestResponse(**evening_digest(tasks, now))
