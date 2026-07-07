"""Day-plan scheduling.

build_day_plan routes tasks around calendar busy blocks — the actual
"auto-mapped day" behavior. Busy blocks are hard no-go zones; tasks are
placed highest-regret-first into the earliest free gap that fits.

Conflict-resolution rule (explicit, tested): a task that fits nowhere in
the remaining open time is returned in `unscheduled` — surfaced to the
client (Today + Review), never silently dropped, never double-booked.

The Claude-API planner may later replace the first-fit heuristic; the
busy-block contract stays.
"""

import datetime as dt
from zoneinfo import ZoneInfo

from app.models import Task

WORK_DAY_START = dt.time(9, 0)
WORK_DAY_END = dt.time(21, 0)
DEFAULT_TASK_MINUTES = 60


def user_today(tz_name: str) -> dt.date:
    try:
        tz = ZoneInfo(tz_name)
    except (KeyError, ValueError):
        tz = dt.timezone.utc
    return dt.datetime.now(tz).date()


def local_midnight(tz_name: str) -> dt.datetime:
    """Start of the user's current day, as an aware datetime."""
    try:
        tz = ZoneInfo(tz_name)
    except (KeyError, ValueError):
        tz = dt.timezone.utc
    return dt.datetime.combine(dt.datetime.now(tz).date(), dt.time.min, tzinfo=tz)


def humanize_due(due_at: dt.datetime | None, now: dt.datetime | None = None) -> str | None:
    """Deadline countdown by actual time-remaining, not calendar day:
    under an hour → minutes, under a day → hours, otherwise days.
    e.g. "due in 25 min" / "due in 6 h" / "due in 3 days" / "overdue by 2 h".
    """
    if due_at is None:
        return None
    now = now or dt.datetime.now(dt.timezone.utc)
    delta = due_at - now
    overdue = delta.total_seconds() < 0
    secs = abs(delta.total_seconds())

    if secs < 3600:
        n = max(1, round(secs / 60))
        unit = f"{n} min"
    elif secs < 86400:
        n = max(1, int(secs // 3600))
        unit = f"{n} h"
    else:
        n = int(secs // 86400)
        unit = f"{n} day{'s' if n != 1 else ''}"

    return f"overdue by {unit}" if overdue else f"due in {unit}"


def _task_minutes(task: Task) -> int:
    minutes = int((task.estimated_hours or 1.0) * 60)
    return max(minutes, 15) if minutes else DEFAULT_TASK_MINUTES


def _pinned_start_minute(
    task: Task, day: dt.date, tz: "ZoneInfo | dt.timezone", day_anchor: dt.datetime
) -> int | None:
    """Minutes-since-midnight of a task's pinned start, or None if it isn't
    pinned (or is pinned to a different day)."""
    pinned = getattr(task, "scheduled_at", None)
    if pinned is None:
        return None
    local = pinned.astimezone(tz)
    if local.date() != day:
        return None
    return int((local - day_anchor).total_seconds() / 60)


def _merge(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def build_day_plan(
    tasks: list[Task],
    busy: list[tuple[dt.datetime, dt.datetime]],
    day: dt.date,
    tz_name: str = "UTC",
    day_start: dt.time = WORK_DAY_START,
    day_end: dt.time = WORK_DAY_END,
    now: dt.datetime | None = None,
) -> tuple[list[dict], list[Task]]:
    """→ (plan slots, unscheduled tasks).

    Slots: {"time": "HH:MM", "task_id": UUID, "duration": minutes}.

    When `now` falls on `day`, the plan starts at the current time (rounded
    up to 5 min), never in the past — a task added at 15:55 must not land
    in a 09:00 slot that already happened.
    """
    try:
        tz = ZoneInfo(tz_name)
    except (KeyError, ValueError):
        tz = dt.timezone.utc

    window_start = day_start.hour * 60 + day_start.minute
    window_end = day_end.hour * 60 + day_end.minute

    if now is not None:
        local_now = now.astimezone(tz)
        if local_now.date() == day:
            now_minutes = local_now.hour * 60 + local_now.minute
            now_minutes = ((now_minutes + 4) // 5) * 5  # round up to :05 marks
            window_start = max(window_start, now_minutes)

    # busy datetimes → minutes-since-midnight on this day, clipped to window
    busy_minutes: list[tuple[int, int]] = []
    day_anchor = dt.datetime.combine(day, dt.time.min, tzinfo=tz)
    for b_start, b_end in busy:
        s = (b_start.astimezone(tz) - day_anchor).total_seconds() / 60
        e = (b_end.astimezone(tz) - day_anchor).total_seconds() / 60
        s, e = max(s, window_start), min(e, window_end)
        if e > s:
            busy_minutes.append((int(s), int(e)))

    slots: list[dict] = []
    unscheduled: list[Task] = []

    # Pinned tasks (user chose a specific time) are fixed anchors: they always
    # get their slot — the explicit choice wins over auto-placement — and they
    # occupy that time so untimed tasks flow around them.
    pinned: list[tuple[Task, int]] = []
    unpinned: list[Task] = []
    for task in tasks:
        start_min = _pinned_start_minute(task, day, tz, day_anchor)
        (unpinned if start_min is None else pinned).append(
            task if start_min is None else (task, start_min)  # type: ignore[arg-type]
        )

    for task, start_min in pinned:
        minutes = _task_minutes(task)
        slots.append(
            {
                "time": f"{start_min // 60:02d}:{start_min % 60:02d}",
                "task_id": task.id,
                "duration": minutes,
            }
        )
        busy_minutes.append((start_min, start_min + minutes))

    # free gaps = window minus merged (calendar busy + pinned tasks)
    free: list[tuple[int, int]] = []
    cursor = window_start
    for b_start, b_end in _merge(busy_minutes):
        if b_start > cursor:
            free.append((cursor, b_start))
        cursor = max(cursor, b_end)
    if cursor < window_end:
        free.append((cursor, window_end))

    # untimed tasks: first-fit, highest regret first
    for task in sorted(unpinned, key=lambda t: t.regret_score, reverse=True):
        minutes = _task_minutes(task)
        placed = False
        for i, (gap_start, gap_end) in enumerate(free):
            if gap_end - gap_start >= minutes:
                slots.append(
                    {
                        "time": f"{gap_start // 60:02d}:{gap_start % 60:02d}",
                        "task_id": task.id,
                        "duration": minutes,
                    }
                )
                free[i] = (gap_start + minutes, gap_end)
                placed = True
                break
        if not placed:
            unscheduled.append(task)

    slots.sort(key=lambda s: s["time"])
    return slots, unscheduled
