import datetime as dt
import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import Task, TaskStatus, Track
from app.schemas.tasks import (
    TaskCreateRequest,
    TaskFullOut,
    TaskPatchRequest,
    TasksResponse,
)
from app.services.scheduling import humanize_due, user_today
from app.services.tracks import find_track

router = APIRouter(prefix="/api", tags=["tasks"])

QUICK_ADD_REGRET = 20  # manual adds start low; the classifier scores email-born tasks


def _task_full_out(task: Task) -> TaskFullOut:
    return TaskFullOut(
        id=task.id,
        track=task.track.slug,
        title=task.title,
        meta=humanize_due(task.due_at),
        regret_score=task.regret_score,
        estimated_hours=task.estimated_hours,
        status=task.status.value,
        pipeline=task.pipeline.value if task.pipeline else None,
        scheduled_for=task.scheduled_for,
        scheduled_at=task.scheduled_at,
        due_at=task.due_at,
        completed_at=task.completed_at,
    )


def due_by_today(today):
    """Filter: tasks that belong to today or earlier (NULL = legacy = today).
    Tomorrow's tasks stay out of Today/Review/the plan until their day."""
    return or_(Task.scheduled_for.is_(None), Task.scheduled_for <= today)


@router.get("/tasks", response_model=TasksResponse)
async def list_tasks(
    user: CurrentUser,
    db: DbSession,
    on: dt.date | None = None,
    start: dt.date | None = None,
    end: dt.date | None = None,
    # Aliased because the rest of the contract is camelCase and a lone
    # snake_case query parameter is exactly the kind of inconsistency a client
    # gets wrong once and then works around forever.
    include_done: Annotated[bool, Query(alias="includeDone")] = False,
) -> TasksResponse:
    """Non-done tasks for today or earlier, highest consequence first.

    `on=YYYY-MM-DD` overrides that to return every task (any status) scheduled
    for exactly that day — powering the calendar's per-date view and the
    Today date-scrubber.

    `start`/`end` return every task in an inclusive date range. The month grid
    needs to know which days have anything on them, and asking day by day meant
    31 round trips to draw one screen — which is why it never asked at all and
    drew its dots for today only.
    """
    stmt = (
        select(Task)
        .where(Task.user_id == user.id)
        .options(selectinload(Task.track))
        .order_by(Task.regret_score.desc())
    )
    if on is not None:
        stmt = stmt.where(Task.scheduled_for == on)
    elif start is not None and end is not None:
        stmt = stmt.where(Task.scheduled_for >= start, Task.scheduled_for <= end)
    else:
        stmt = stmt.where(due_by_today(user_today(user.timezone)))
        # `include_done` keeps today's completed work in the list. The app shows
        # a ticked task struck through rather than removing it — a task that
        # disappears the moment you complete it reads as having been deleted —
        # so without this the next refresh would silently take them all away
        # again.
        if not include_done:
            stmt = stmt.where(Task.status != TaskStatus.done)
    tasks = (await db.scalars(stmt)).all()
    return TasksResponse(tasks=[_task_full_out(t) for t in tasks])


@router.post("/tasks", response_model=TaskFullOut, status_code=201)
async def create_task(
    body: TaskCreateRequest, user: CurrentUser, db: DbSession
) -> TaskFullOut:
    title = body.title.strip()
    if not title:
        raise AskcalError(422, "INVALID_TASK", "Title is empty")
    # Looked up by slug against this account's own tracks. There is no valid
    # list to check against first — what exists is whatever the user made.
    track = await find_track(db, user.id, body.track)
    if track is None:
        raise AskcalError(422, "INVALID_TRACK", f"No '{body.track}' track on this account")

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


@router.delete("/tasks/{task_id}", status_code=204)
async def delete_task(task_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    """Remove a task outright.

    The undo for auto-tasking. Without this the only way to clear a wrongly
    created task was to mark it done, so every false positive accumulated
    permanently — which is what made over-creation feel bad rather than merely
    noisy.

    The source email deliberately stays `handled`: deleting the task means "this
    was never work", so putting the mail back in the inbox would just ask the
    same question again.
    """
    task = await db.scalar(
        select(Task).where(Task.user_id == user.id, Task.id == task_id)
    )
    if task is None:
        raise AskcalError(404, "NOT_FOUND", "No such task")
    await db.delete(task)
    await db.commit()


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
            # Move the day it lives on, not just the label. Marking it carried
            # and leaving scheduled_for on today meant "move to tomorrow" moved
            # nothing: the task stayed filed against today forever, dropped out
            # of the day list because of its status, and never reappeared on any
            # other day. Carried work was simply lost.
            task.scheduled_for = user_today(user.timezone) + dt.timedelta(days=1)

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