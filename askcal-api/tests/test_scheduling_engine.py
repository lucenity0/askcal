"""build_day_plan: busy blocks are hard no-go zones; overflow is surfaced."""

import datetime as dt
import uuid
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.services.scheduling import build_day_plan, humanize_due

TZ = "UTC"
DAY = dt.date(2026, 7, 8)


def task(score: int, hours: float | None = 1.0, scheduled_at: dt.datetime | None = None,
         due_at: dt.datetime | None = None):
    return SimpleNamespace(
        id=uuid.uuid4(), regret_score=score, estimated_hours=hours,
        scheduled_at=scheduled_at, due_at=due_at,
    )


def at(hour: int, minute: int = 0, day: dt.date = DAY) -> dt.datetime:
    return dt.datetime.combine(day, dt.time(hour, minute), tzinfo=ZoneInfo(TZ))


def busy(start_h: int, start_m: int, end_h: int, end_m: int):
    tz = ZoneInfo(TZ)
    return (
        dt.datetime.combine(DAY, dt.time(start_h, start_m), tzinfo=tz),
        dt.datetime.combine(DAY, dt.time(end_h, end_m), tzinfo=tz),
    )


def slot_range(slot) -> tuple[int, int]:
    h, m = map(int, slot["time"].split(":"))
    start = h * 60 + m
    return start, start + slot["duration"]


def test_open_day_schedules_sequentially_by_regret():
    tasks = [task(30, 1.0), task(80, 2.0), task(50, 1.0)]
    slots, unscheduled = build_day_plan(tasks, [], DAY, TZ)
    assert unscheduled == []
    assert slots[0]["time"] == "09:00"
    # highest regret gets the first slot
    assert slots[0]["task_id"] == tasks[1].id
    # no overlaps
    ranges = sorted(slot_range(s) for s in slots)
    for (_, e1), (s2, _) in zip(ranges, ranges[1:], strict=False):
        assert e1 <= s2


def test_tasks_route_around_busy_blocks():
    # 10:00–12:00 lecture: a 3h task can't fit before it (only 1h open)
    tasks = [task(90, 3.0), task(40, 1.0)]
    slots, unscheduled = build_day_plan(tasks, [busy(10, 0, 12, 0)], DAY, TZ)
    assert unscheduled == []
    by_id = {s["task_id"]: s for s in slots}
    big, small = by_id[tasks[0].id], by_id[tasks[1].id]
    assert big["time"] == "12:00"     # placed after the lecture
    assert small["time"] == "09:00"   # the 1h task fills the morning gap
    # nothing intersects the busy block
    for s in slots:
        start, end = slot_range(s)
        assert end <= 10 * 60 or start >= 12 * 60


def test_overflow_is_surfaced_not_dropped_or_double_booked():
    # back-to-back events 09:00–20:00 leave one open hour (20–21);
    # 5 task-hours cannot fit — overflow must be explicit
    blocks = [busy(9, 0, 13, 0), busy(13, 0, 17, 0), busy(17, 0, 20, 0)]
    tasks = [task(90, 2.0), task(80, 2.0), task(70, 1.0)]
    slots, unscheduled = build_day_plan(tasks, blocks, DAY, TZ)

    # exactly the 1h task fits in the 20:00 gap
    assert len(slots) == 1
    assert slots[0]["task_id"] == tasks[2].id
    assert slots[0]["time"] == "20:00"
    # the two 2h tasks are surfaced as unscheduled — never silently dropped
    assert {t.id for t in unscheduled} == {tasks[0].id, tasks[1].id}
    # and never double-booked into busy time
    start, end = slot_range(slots[0])
    assert start >= 20 * 60 and end <= 21 * 60


def test_fully_blocked_day_schedules_nothing_and_does_not_crash():
    slots, unscheduled = build_day_plan(
        [task(90, 1.0)], [busy(9, 0, 21, 0)], DAY, TZ
    )
    assert slots == []
    assert len(unscheduled) == 1


def test_overlapping_busy_blocks_are_merged():
    # 09–11 and 10–12 overlap → treated as 09–12
    tasks = [task(60, 1.0)]
    slots, _ = build_day_plan(tasks, [busy(9, 0, 11, 0), busy(10, 0, 12, 0)], DAY, TZ)
    assert slots[0]["time"] == "12:00"


def _at(hour: int, minute: int) -> dt.datetime:
    return dt.datetime.combine(DAY, dt.time(hour, minute), tzinfo=ZoneInfo(TZ))


def test_plan_never_starts_in_the_past():
    # it's 15:53 — nothing may be slotted before now (rounded up to 15:55)
    tasks = [task(80, 1.0), task(40, 1.0)]
    slots, unscheduled = build_day_plan(tasks, [], DAY, TZ, now=_at(15, 53))
    assert unscheduled == []
    assert slots[0]["time"] == "15:55"
    for s in slots:
        start, _ = slot_range(s)
        assert start >= 15 * 60 + 55


def test_now_on_another_day_does_not_clip():
    # planning tomorrow while it's this evening → full window available
    yesterday_evening = dt.datetime.combine(
        DAY - dt.timedelta(days=1), dt.time(22, 0), tzinfo=ZoneInfo(TZ)
    )
    slots, _ = build_day_plan([task(50, 1.0)], [], DAY, TZ, now=yesterday_evening)
    assert slots[0]["time"] == "09:00"


def test_after_hours_everything_is_unscheduled():
    # 21:30 — the working window is over; tasks surface as unscheduled
    slots, unscheduled = build_day_plan([task(50, 1.0)], [], DAY, TZ, now=_at(21, 30))
    assert slots == []
    assert len(unscheduled) == 1


# ── Pinned tasks (user-chosen time) ─────────────────────────────────────────

def test_pinned_task_lands_at_its_chosen_time():
    pinned = task(20, 1.0, scheduled_at=_at(14, 0))
    slots, unscheduled = build_day_plan([pinned], [], DAY, TZ)
    assert unscheduled == []
    assert slots[0]["time"] == "14:00"
    assert slots[0]["task_id"] == pinned.id


def test_untimed_tasks_flow_around_a_pin():
    # a 2h pin at 10:00 blocks 10–12; the 1h untimed task takes the 09:00 gap
    pinned = task(30, 2.0, scheduled_at=_at(10, 0))
    floating = task(90, 1.0)
    slots, unscheduled = build_day_plan([pinned, floating], [], DAY, TZ)
    assert unscheduled == []
    by_id = {s["task_id"]: s for s in slots}
    assert by_id[pinned.id]["time"] == "10:00"
    assert by_id[floating.id]["time"] == "09:00"  # before the pin, not overlapping


def test_pin_wins_over_now_clip():
    # pinned at 08:00 even though it's already 15:00 — an explicit choice
    # is honored, unlike auto-placement which never lands in the past
    pinned = task(20, 1.0, scheduled_at=_at(8, 0))
    slots, _ = build_day_plan([pinned], [], DAY, TZ, now=_at(15, 0))
    assert slots[0]["time"] == "08:00"


# ── Deadline humanization (time-remaining granularity) ──────────────────────

def test_humanize_minutes_hours_days():
    now = _at(12, 0)
    assert humanize_due(_at(12, 25), now) == "due in 25 min"
    assert humanize_due(_at(18, 0), now) == "due in 6 h"
    assert humanize_due(DAY_PLUS(3, 12, 0), now) == "due in 3 days"


def test_humanize_overdue_and_none():
    now = _at(12, 0)
    assert humanize_due(_at(11, 30), now) == "overdue by 30 min"
    assert humanize_due(None, now) is None


def DAY_PLUS(days: int, hour: int, minute: int) -> dt.datetime:
    return dt.datetime.combine(
        DAY + dt.timedelta(days=days), dt.time(hour, minute), tzinfo=ZoneInfo(TZ)
    )


# ── Deadlines are a constraint, not a preference ────────────────────────────


def test_a_deadline_today_outranks_a_higher_score_without_one():
    """Regret alone put the one thing with a wall after everything else."""
    loose = task(90, 1.0)                      # scores higher
    due_at_five = task(30, 1.0, due_at=at(17))  # but has to be done by 17:00
    slots, unscheduled = build_day_plan([loose, due_at_five], [], DAY, TZ)

    assert unscheduled == []
    assert slots[0]["task_id"] == due_at_five.id


def test_the_soonest_deadline_leads():
    late = task(80, 1.0, due_at=at(16))
    soon = task(20, 1.0, due_at=at(11))
    slots, _ = build_day_plan([late, soon], [], DAY, TZ)

    assert slots[0]["task_id"] == soon.id


def test_a_task_is_placed_so_it_finishes_before_its_deadline():
    # 09:00-11:00 is blocked, so first-fit would land this at 11:00 and
    # finish at 13:00 — an hour after it was due.
    due_at_noon = task(50, 2.0, due_at=at(12))
    slots, unscheduled = build_day_plan([due_at_noon], [busy(9, 0, 10, 0)], DAY, TZ)

    assert unscheduled == []
    start, end = slot_range(slots[0])
    assert end <= 12 * 60, "scheduled to finish after its own deadline"


def test_an_impossible_deadline_is_still_scheduled_rather_than_dropped():
    """Late is more use than absent — and hiding it hides the one task that
    most needs looking at."""
    impossible = task(70, 3.0, due_at=at(9, 30))
    slots, unscheduled = build_day_plan([impossible], [], DAY, TZ)

    assert unscheduled == []
    assert len(slots) == 1


def test_tomorrows_deadline_does_not_compress_today():
    tomorrow = DAY + dt.timedelta(days=1)
    later = task(20, 1.0, due_at=at(9, 0, tomorrow))
    urgent_today = task(85, 1.0)
    slots, _ = build_day_plan([later, urgent_today], [], DAY, TZ)

    # No deadline lands on this day, so consequence decides as it always did.
    assert slots[0]["task_id"] == urgent_today.id
