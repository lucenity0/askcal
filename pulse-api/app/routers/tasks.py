import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from app.core.errors import PulseError
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


def _task_full_out(task: Task, today) -> TaskFullOut:
    return TaskFullOut(
        id=task.id,
        track=task.track.key.value,
        title=task.title,
        meta=humanize_due(task.due_at, today),
        regret_score=task.regret_score,
        estimated_hours=task.estimated_hours,
        status=task.status.value,
        pipeline=task.pipeline.value if task.pipeline else None,
        scheduled_for=task.scheduled_for,
    )


def due_by_today(today):
    """Filter: tasks that belong to today or earlier (NULL = legacy = today).
    Tomorrow's tasks stay out of Today/Review/the plan until their day."""
    return or_(Task.scheduled_for.is_(None), Task.scheduled_for <= today)


@router.get("/tasks", response_model=TasksResponse)
async def list_tasks(user: CurrentUser, db: DbSession) -> TasksResponse:
    """All non-done tasks for today or earlier, highest consequence first."""
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
    return TasksResponse(tasks=[_task_full_out(t, today) for t in tasks])


@router.post("/tasks", response_model=TaskFullOut, status_code=201)
async def create_task(
    body: TaskCreateRequest, user: CurrentUser, db: DbSession
) -> TaskFullOut:
    title = body.title.strip()
    if not title:
        raise PulseError(422, "INVALID_TASK", "Title is empty")
    try:
        track_key = TrackKey(body.track)
    except ValueError:
        raise PulseError(422, "INVALID_TRACK", f"Unknown track '{body.track}'")
    track = await db.scalar(
        select(Track).where(Track.user_id == user.id, Track.key == track_key)
    )
    if track is None:
        raise PulseError(422, "INVALID_TRACK", f"No '{track_key.value}' track on this account")

    today = user_today(user.timezone)
    task = Task(
        user_id=user.id,
        track_id=track.id,
        title=title,
        regret_score=QUICK_ADD_REGRET,
        estimated_hours=body.estimated_hours,
        scheduled_for=today + timedelta(days=1) if body.when == "tomorrow" else today,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task, ["track"])
    return _task_full_out(task, today)


@router.patch("/tasks/{task_id}", response_model=TaskFullOut)
async def patch_task(
    task_id: uuid.UUID, body: TaskPatchRequest, user: CurrentUser, db: DbSession
) -> TaskFullOut:
    try:
        status = TaskStatus(body.status)
    except ValueError:
        raise PulseError(422, "INVALID_STATUS", f"Unknown status '{body.status}'")

    task = await db.scalar(
        select(Task)
        .where(Task.user_id == user.id, Task.id == task_id)
        .options(selectinload(Task.track))
    )
    if task is None:
        raise PulseError(404, "NOT_FOUND", "No such task")

    task.status = status
    if status == TaskStatus.done:
        task.completed_at = datetime.now(timezone.utc)
    elif status == TaskStatus.carried:
        task.carried_count += 1
    await db.commit()
    return _task_full_out(task, user_today(user.timezone))