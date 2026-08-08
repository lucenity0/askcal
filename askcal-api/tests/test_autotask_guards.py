"""The gates added to stop auto-tasking from over-creating.

The old rule was effectively "the model said action_required", and its mistakes
were permanent because there was no way to delete a task. These pin the floors,
the deadline sanitising, and deadline-driven scheduling.
"""

import datetime as dt
from datetime import timezone
from types import SimpleNamespace

import pytest

from app.config import get_settings
from app.models import TrackKey
from app.services.autotask import (
    sanitize_deadline,
    scheduled_day_for,
    should_auto_task,
)
from app.services.classifier import EmailSignals

RECEIVED = dt.datetime(2026, 8, 8, 9, 0, tzinfo=timezone.utc)
TODAY = dt.date(2026, 8, 8)


@pytest.fixture(autouse=True)
def _fresh_settings():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def signals(**over) -> EmailSignals:
    base = {
        "gmail_id": "g1",
        "track": "uni",
        "sender_type": "professor",
        "consequence": "grade_loss",
        "action_required": True,
        "confidence": 0.9,
    }
    base.update(over)
    return EmailSignals(**base)


def track_row(active: bool = True):
    return SimpleNamespace(active=active, weight=1.0)


# ── confidence floor ──────────────────────────────────────────────────────


def test_a_confident_classification_still_tasks():
    assert should_auto_task(signals(), TrackKey.uni, track_row(), 70)


def test_a_guess_does_not_become_a_task():
    """confidence used only to dampen the score; it never gated creation.

    A 0.05 guess produced a task identical to a 0.99 certainty.
    """
    assert not should_auto_task(signals(confidence=0.2), TrackKey.uni, track_row(), 70)


def test_the_confidence_floor_is_configurable(monkeypatch):
    monkeypatch.setenv("ASKCAL_AUTO_TASK_MIN_CONFIDENCE", "0.95")
    get_settings.cache_clear()
    assert not should_auto_task(signals(confidence=0.9), TrackKey.uni, track_row(), 70)


# ── regret floor ──────────────────────────────────────────────────────────


def test_a_trivially_scored_item_does_not_become_a_task():
    """regret_score was computed one line above the decision and never read."""
    assert not should_auto_task(signals(), TrackKey.uni, track_row(), 5)


def test_the_regret_floor_is_skipped_when_no_score_is_supplied():
    """Keeps the predicate callable without a scored email."""
    assert should_auto_task(signals(), TrackKey.uni, track_row(), None)


# ── the gates that already existed still hold ─────────────────────────────


def test_no_action_required_never_tasks():
    assert not should_auto_task(
        signals(action_required=False), TrackKey.uni, track_row(), 70
    )


@pytest.mark.parametrize("consequence", ["social", "none"])
def test_zero_stakes_never_tasks(consequence):
    assert not should_auto_task(
        signals(consequence=consequence), TrackKey.uni, track_row(), 70
    )


def test_feed_never_tasks():
    assert not should_auto_task(signals(track="feed"), TrackKey.feed, track_row(), 70)


def test_an_inactive_track_never_tasks():
    assert not should_auto_task(signals(), TrackKey.uni, track_row(active=False), 70)


def test_automated_senders_still_task():
    """The assignment-not-tasking regression: sender is deliberately not a gate."""
    assert should_auto_task(
        signals(sender_type="automated_system"), TrackKey.uni, track_row(), 70
    )


# ── deadline sanitising ───────────────────────────────────────────────────


def test_a_plausible_deadline_survives():
    got = sanitize_deadline("2026-08-20T23:59:00Z", RECEIVED)
    assert got == dt.datetime(2026, 8, 20, 23, 59, tzinfo=timezone.utc)


def test_a_hallucinated_far_future_deadline_is_dropped():
    assert sanitize_deadline("2199-01-01T00:00:00Z", RECEIVED) is None


def test_a_hallucinated_past_deadline_is_dropped():
    """A garbage past date otherwise reads as maximally urgent forever.

    The regret formula buckets anything within 24 hours — including negatives —
    at its highest deadline score.
    """
    assert sanitize_deadline("1970-01-01T00:00:00Z", RECEIVED) is None


def test_a_recently_overdue_deadline_is_kept():
    """Genuinely overdue work is still work."""
    assert sanitize_deadline("2026-08-01T09:00:00Z", RECEIVED) is not None


def test_garbage_and_none_stay_none():
    assert sanitize_deadline("whenever bro", RECEIVED) is None
    assert sanitize_deadline(None, RECEIVED) is None


# ── deadline-driven scheduling ────────────────────────────────────────────


def test_no_deadline_schedules_for_today():
    assert scheduled_day_for(None, TODAY) == TODAY


def test_a_distant_deadline_does_not_land_on_today():
    """Everything used to be scheduled_for=today, inflating the day's plan."""
    due = dt.datetime(2026, 8, 29, 23, 59, tzinfo=timezone.utc)
    assert scheduled_day_for(due, TODAY) == dt.date(2026, 8, 28)


def test_an_imminent_deadline_lands_on_today():
    due = dt.datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)
    assert scheduled_day_for(due, TODAY) == TODAY


def test_an_overdue_deadline_lands_on_today_not_in_the_past():
    """Overdue work belongs on today's list, not the day it was missed."""
    due = dt.datetime(2026, 8, 1, 12, 0, tzinfo=timezone.utc)
    assert scheduled_day_for(due, TODAY) == TODAY
