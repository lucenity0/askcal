"""Day-plan helpers.

naive_day_plan is a placeholder: the real plan generation is one Claude API
call per day (later phase). This keeps GET /api/today contract-complete
until then.
"""

import datetime as dt
from zoneinfo import ZoneInfo

from app.models import Task

WORK_DAY_START = dt.time(9, 0)
DEFAULT_TASK_MINUTES = 60
MAX_PLAN_SLOTS = 6


def user_today(tz_name: str) -> dt.date:
    try:
        tz = ZoneInfo(tz_name)
    except (KeyError, ValueError):
        tz = dt.timezone.utc
    return dt.datetime.now(tz).date()


def humanize_due(due_at: dt.datetime | None, today: dt.date) -> str | None:
    """"due today" / "due tomorrow" / "due in N days" / "overdue by N days"."""
    if due_at is None:
        return None
    days = (due_at.date() - today).days
    if days < 0:
        return f"overdue by {-days} day{'s' if days != -1 else ''}"
    if days == 0:
        return "due today"
    if days == 1:
        return "due tomorrow"
    return f"due in {days} days"


def naive_day_plan(tasks: list[Task]) -> list[dict]:
    """Sequential blocks from 09:00, highest regret first."""
    plan = []
    cursor = dt.datetime.combine(dt.date.today(), WORK_DAY_START)
    for task in tasks[:MAX_PLAN_SLOTS]:
        minutes = int((task.estimated_hours or 1.0) * 60) or DEFAULT_TASK_MINUTES
        plan.append(
            {"time": cursor.strftime("%H:%M"), "task_id": task.id, "duration": minutes}
        )
        cursor += dt.timedelta(minutes=minutes)
    return plan
