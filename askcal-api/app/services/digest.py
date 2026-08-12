"""What the two daily notifications actually say.

The morning digest and the evening nudge fired with fixed text — "your day is
ready", "close the day" — which is a reminder that something exists, not a
reason to open it. A notification that tells you nothing trains you to swipe it
away.

Both summaries are assembled here rather than in the routers so the notification
copy and the screen behind it come from one place. If they can drift, they will,
and a push that promises three deadlines opening onto a screen showing two is
worse than no push.
"""

import datetime as dt

from app.models import Email, Task, TaskStatus
from app.services.triage import mail_need

__all__ = ["morning_digest", "evening_digest"]


def _plural(n: int, one: str, many: str | None = None) -> str:
    return f"{n} {one}" if n == 1 else f"{n} {many or one + 's'}"


def morning_digest(
    tasks: list[Task],
    emails: list[Email],
    plan: list[dict],
    now: dt.datetime,
) -> dict:
    """What today asks of you, before you have looked at it.

    Deliberately leads with deadlines rather than volume. "Nine things" is a
    number that makes a morning worse; "two due today, first at 11:00" is one
    you can act on.
    """
    open_tasks = [t for t in tasks if t.status != TaskStatus.done]
    due_today = [t for t in open_tasks if _due_on(t, now)]
    carried = [t for t in open_tasks if t.status == TaskStatus.carried]

    needs = [mail_need(e.signals, now) for e in emails]
    replies = sum(1 for n in needs if n == "reply")
    deadlines = sum(1 for n in needs if n == "deadline")

    first = plan[0] if plan else None
    planned_minutes = sum(s.get("duration", 0) for s in plan)

    return {
        "date": now.date(),
        "headline": _morning_headline(due_today, open_tasks, first),
        "task_count": len(open_tasks),
        "due_today": len(due_today),
        "carried_over": len(carried),
        "first_slot": first.get("time") if first else None,
        "planned_minutes": planned_minutes,
        "needs_reply": replies,
        "mail_with_deadlines": deadlines,
        "lines": _morning_lines(due_today, carried, replies, planned_minutes),
    }


def _morning_headline(due_today: list[Task], open_tasks: list[Task], first) -> str:
    if not open_tasks:
        return "Nothing on today."
    if due_today:
        at = f", first at {first['time']}" if first else ""
        return f"{_plural(len(due_today), 'thing')} due today{at}."
    if first:
        return f"{_plural(len(open_tasks), 'thing')} on. Starts {first['time']}."
    return f"{_plural(len(open_tasks), 'thing')} on, no fixed times."


def _morning_lines(
    due_today: list[Task], carried: list[Task], replies: int, planned: int
) -> list[str]:
    lines: list[str] = []
    for task in due_today[:3]:
        lines.append(task.title)
    if carried:
        lines.append(f"{_plural(len(carried), 'thing')} moved from yesterday")
    if replies:
        lines.append(f"{_plural(replies, 'mail')} waiting on a reply")
    if planned:
        hours, minutes = divmod(planned, 60)
        span = f"{hours}h {minutes}m" if hours else f"{minutes}m"
        lines.append(f"{span} planned")
    return lines


def evening_digest(tasks: list[Task], now: dt.datetime, streak: int = 0) -> dict:
    """How the day actually went.

    Counts what happened rather than what is left, because this fires when
    there is nothing more to be done about it — a list of what you did not
    finish, at 9pm, is just a way to feel bad.
    """
    done = [t for t in tasks if t.status == TaskStatus.done]
    carried = [t for t in tasks if t.status == TaskStatus.carried]
    still_open = [
        t for t in tasks if t.status not in (TaskStatus.done, TaskStatus.carried)
    ]

    return {
        "date": now.date(),
        "headline": _evening_headline(done, still_open),
        "done": len(done),
        "carried": len(carried),
        "still_open": len(still_open),
        "streak": streak,
        "lines": [t.title for t in done[:3]],
    }


def _evening_headline(done: list[Task], still_open: list[Task]) -> str:
    if not done and not still_open:
        return "Nothing was on today."
    if not still_open:
        return f"All done — {_plural(len(done), 'thing')} closed out."
    if not done:
        return f"{_plural(len(still_open), 'thing')} still open."
    return f"{_plural(len(done), 'thing')} done, {len(still_open)} still open."


def _due_on(task: Task, now: dt.datetime) -> bool:
    """Whether the task's deadline falls on the day `now` is in.

    Compared in the timezone `now` carries, which the caller has already set to
    the user's — comparing in UTC would move the boundary by hours and drop
    late-evening deadlines out of the day they belong to.
    """
    if task.due_at is None:
        return False
    return task.due_at.astimezone(now.tzinfo).date() == now.date()
