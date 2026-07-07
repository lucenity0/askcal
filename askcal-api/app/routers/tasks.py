import datetime as dt
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import Task, TaskStatus, Track, TrackKey
from app.schemas.tasks import (
    TaskCreateRequest,
    TaskFullOut,
    TaskPatchRequest,
    TasksResponse,
)
from app.services.scheduling import humanize_due, user_today

router = APIRouter(prefix="/api", tags=["tasks"])

QUICK_ADD_REGRET = 20  # manual adds start low; the classifier scores email-born tasks


def _task_full_out(task: Task) -> TaskFullOut:
    return TaskFullOut(
        id=task.id,
        track=task.track.key.value,
        title=task.title,
        meta=humanize_due(task.due_at),
        regret_score=task.regret_score,
        estimated_hours=task.estimated_hours,
        status=task.status.value,
        pipeline=task.pipeline.value if task.pipeline else None,
        scheduled_for=task.scheduled_for,
        scheduled_at=task.scheduled_at,
        due_at=task.due_at,
    )


def due_by_today(today):
    """Filter: tasks that belong to today or earlier (NULL = legacy = today).
    Tomorrow's tasks stay out of Today/Review/the plan until their day."""
    return or_(Task.scheduled_for.is_(None), Task.scheduled_for <= today)


@router.get("/tasks", response_model=TasksResponse)
async def list_tasks(
    user: CurrentUser, db: DbSession, on: dt.date | None = None
) -> TasksResponse:
    """Non-done tasks for today or earlier, highest consequence first.

    `on=YYYY-MM-DD` overrides that to return every task (any status) scheduled
    for exactly that day — powering the calendar's per-date view and the
    Today date-scrubber.
    """
    stmt = (
        select(Task)
        .where(Task.user_id == user.id)
        .options(selectinload(Task.track))
        .order_by(Task.regret_score.desc())
    )
    if on is not None:
        stmt = stmt.where(Task.scheduled_for == on)
    else:
        stmt = stmt.where(
            Task.status != TaskStatus.done, due_by_today(user_today(user.timezone))
        )
    tasks = (await db.scalars(stmt)).all()
    return TasksResponse(tasks=[_task_full_out(t) for t in tasks])


@router.post("/tasks", response_model=TaskFullOut, status_code=201)
async def create_task(
    body: TaskCreateRequest, user: CurrentUser, db: DbSession
) -> TaskFullOut:
    title = body.title.strip()
    if not title:
        raise AskcalError(422, "INVALID_TASK", "Title is empty")
    try:
        track_key = TrackKey(body.track)
    except ValueError:
        raise AskcalError(422, "INVALID_TRACK", f"Unknown track '{body.track}'")
    track = await db.scalar(
        select(Track).where(Track.user_id == user.id, Track.key == track_key)
    )
    if track is None:
        raise AskcalError(422, "INVALID_TRACK", f"No '{track_key.value}' track on this account")

    # scheduled_for defaults to the pinned time's day, else today
    scheduled_for = body.scheduled_for
    if scheduled_for is None:
        scheduled_for = (
            body.scheduled_at.astimezone(timezone.utc).date()
            if body.scheduled_at
            else user_today(user.timezone)
        )

    task = Task(
        user_id=user.id,
        track_id=track.id,
        title=title,
        regret_score=QUICK_ADD_REGRET,
        estimated_hours=body.estimated_hours,
        scheduled_for=scheduled_for,
        scheduled_at=body.scheduled_at,
        due_at=body.due_at,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task, ["track"])
    return _task_full_out(task)


@router.patch("/tasks/{task_id}", response_model=TaskFullOut)
async def patch_task(
    task_id: uuid.UUID, body: TaskPatchRequest, user: CurrentUser, db: DbSession
) -> TaskFullOut:
    task = await db.scalar(
        select(Task)
        .where(Task.user_id == user.id, Task.id == task_id)
        .options(selectinload(Task.track))
    )
    if task is None:
        raise AskcalError(404, "NOT_FOUND", "No such task")

    fields = body.model_fields_set  # only touch what the client actually sent

    if "status" in fields and body.status is not None:
        try:
            status = TaskStatus(body.status)
        except ValueError:
            raise AskcalError(422, "INVALID_STATUS", f"Unknown status '{body.status}'")
        task.status = status
        if status == TaskStatus.done:
            task.completed_at = datetime.now(timezone.utc)
        elif status == TaskStatus.carried:
            task.carried_count += 1

    # editing the schedule / deadline (shift a task to another day or time)
    if "scheduled_at" in fields:
        task.scheduled_at = body.scheduled_at
    if "due_at" in fields:
        task.due_at = body.due_at
    if "scheduled_for" in fields and body.scheduled_for is not None:
        task.scheduled_for = body.scheduled_for
    elif "scheduled_at" in fields and body.scheduled_at is not None:
        # keep the day bucket consistent with a newly pinned time
        task.scheduled_for = body.scheduled_at.astimezone(timezone.utc).date()

    await db.commit()
    return _task_full_out(task)