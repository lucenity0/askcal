"""Auto-task rule: actionable + real active track → task; everything else waits."""

from types import SimpleNamespace

from app.models import TrackKey
from app.services.classifier import EmailSignals
from app.services.sync import AUTO_TASK_TRACKS, should_auto_task


def signals(track: str = "uni", action_required: bool = True) -> EmailSignals:
    return EmailSignals(
        gmail_id="g1",
        track=track,
        sender_type="professor",
        consequence="grade_loss",
        action_required=action_required,
        confidence=0.9,
    )


def track_row(active: bool = True):
    return SimpleNamespace(active=active, weight=1.0)


def test_actionable_email_on_active_track_auto_tasks():
    for key in (TrackKey.uni, TrackKey.career, TrackKey.design, TrackKey.finance):
        assert should_auto_task(signals(key.value), key, track_row()) is True


def test_no_action_required_stays_in_inbox():
    assert should_auto_task(signals(action_required=False), TrackKey.uni, track_row()) is False


def test_feed_never_auto_tasks():
    assert TrackKey.feed not in AUTO_TASK_TRACKS
    assert should_auto_task(signals("feed"), TrackKey.feed, track_row()) is False


def test_unclassified_track_stays_in_inbox():
    assert should_auto_task(signals("none", True), None, None) is False


def test_dormant_track_stays_in_inbox():
    # design inactive (no freelance work in profile) → manual triage only
    assert should_auto_task(signals("design"), TrackKey.design, track_row(active=False)) is False
