"""What the two daily notifications say.

These fire when nobody is looking at the app, so the copy has to be right
without anyone checking it. The counting is the part that goes wrong quietly.
"""

import datetime as dt
import uuid
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.models import TaskStatus
from app.services.digest import evening_digest, morning_digest

IST = ZoneInfo("Asia/Kolkata")
NOW = dt.datetime(2026, 8, 12, 8, 30, tzinfo=IST)


def task(title="a thing", status=TaskStatus.pending, due_at=None):
    return SimpleNamespace(id=uuid.uuid4(), title=title, status=status, due_at=due_at)


def slot(time="09:00", duration=60):
    return {"time": time, "task_id": uuid.uuid4(), "duration": duration}


def mail(**signals):
    base = {"action_required": False, "sender_type": "other",
            "consequence": "none", "deadline_utc": None}
    base.update(signals)
    return SimpleNamespace(signals=base)


# ── Morning ────────────────────────────────────────────────────────────────


def test_an_empty_day_says_so_rather_than_counting_zero():
    d = morning_digest([], [], [], NOW)
    assert d["headline"] == "Nothing on today."
    assert d["lines"] == []


def test_deadlines_lead_rather_than_volume():
    """'Nine things' makes a morning worse; 'two due today' can be acted on."""
    due = dt.datetime(2026, 8, 12, 17, 0, tzinfo=IST)
    tasks = [task("submit", due_at=due), task("read"), task("email"), task("gym")]
    d = morning_digest(tasks, [], [slot("11:00")], NOW)

    assert "1 thing due today" in d["headline"]
    assert "first at 11:00" in d["headline"]
    assert d["due_today"] == 1
    assert d["task_count"] == 4


def test_a_deadline_tomorrow_is_not_due_today():
    tomorrow = dt.datetime(2026, 8, 13, 9, 0, tzinfo=IST)
    d = morning_digest([task(due_at=tomorrow)], [], [], NOW)
    assert d["due_today"] == 0


def test_a_late_evening_deadline_still_belongs_to_today():
    """Compared in the user's timezone. In UTC this is the 12th at 18:30, but
    an 23:59 IST deadline is unambiguously today for the person holding it."""
    tonight = dt.datetime(2026, 8, 12, 23, 59, tzinfo=IST)
    d = morning_digest([task(due_at=tonight)], [], [], NOW)
    assert d["due_today"] == 1


def test_completed_work_is_not_counted_as_still_to_do():
    tasks = [task("done one", status=TaskStatus.done), task("open one")]
    d = morning_digest(tasks, [], [], NOW)
    assert d["task_count"] == 1


def test_mail_waiting_on_a_reply_is_surfaced():
    emails = [
        mail(action_required=True, sender_type="professor", consequence="grade_loss"),
        mail(sender_type="newsletter"),
    ]
    d = morning_digest([task()], emails, [], NOW)
    assert d["needs_reply"] == 1
    assert any("waiting on a reply" in line for line in d["lines"])


def test_the_days_work_is_named_even_when_nothing_is_due():
    """"2 things on" is a number. The titles are what you can act on."""
    d = morning_digest([task("read chapter 4"), task("email supervisor")], [], [], NOW)
    assert "read chapter 4" in d["lines"]
    assert "email supervisor" in d["lines"]


def test_mail_carrying_a_deadline_is_surfaced():
    """This was counted and then dropped, which hid the most consequential
    number in the whole digest."""
    emails = [mail(deadline_utc="2026-08-20T09:00:00Z") for _ in range(9)]
    d = morning_digest([task()], emails, [], NOW)
    assert d["mail_with_deadlines"] == 9
    assert any("9 mails with a date on it" in line for line in d["lines"])


def test_planned_time_reads_as_hours_and_minutes():
    d = morning_digest([task()], [], [slot(duration=90)], NOW)
    assert any("1h 30m planned" in line for line in d["lines"])


# ── Evening ────────────────────────────────────────────────────────────────


def test_a_finished_day_says_all_done():
    tasks = [task(status=TaskStatus.done), task(status=TaskStatus.done)]
    d = evening_digest(tasks, NOW, streak=3)
    assert "All done" in d["headline"]
    assert d["done"] == 2
    assert d["still_open"] == 0


def test_carried_work_is_not_counted_as_still_open():
    """It has been dealt with — moved deliberately, not left behind."""
    tasks = [task(status=TaskStatus.done), task(status=TaskStatus.carried)]
    d = evening_digest(tasks, NOW, streak=1)
    assert d["carried"] == 1
    assert d["still_open"] == 0
    assert "All done" in d["headline"]


def test_a_mixed_day_reports_both_sides():
    tasks = [task(status=TaskStatus.done), task(), task()]
    d = evening_digest(tasks, NOW, streak=0)
    assert d["done"] == 1
    assert d["still_open"] == 2
    assert "1 thing done" in d["headline"]


def test_an_unfinished_day_names_what_is_left_to_decide_about():
    """Closing the day means deciding about those, so they have to be nameable
    from the notification."""
    tasks = [task("submit form"), task("call bank")]
    d = evening_digest(tasks, NOW, streak=0)
    assert "submit form" in d["lines"]
    assert "call bank" in d["lines"]


def test_an_empty_day_does_not_pretend_something_happened():
    d = evening_digest([], NOW, streak=0)
    assert d["headline"] == "Nothing was on today."
