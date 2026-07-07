"""build_day_plan: busy blocks are hard no-go zones; overflow is surfaced."""

import datetime as dt
import uuid
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.services.scheduling import build_day_plan

TZ = "UTC"
DAY = dt.date(2026, 7, 8)


def task(score: int, hours: float | None = 1.0):
    return SimpleNamespace(id=uuid.uuid4(), regret_score=score, estimated_hours=hours)


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
    for (s1, e1), (s2, _) in zip(ranges, ranges[1:]):
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
