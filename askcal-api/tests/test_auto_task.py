"""Auto-task rule coverage.

A mail becomes a task when the model says the user must personally do a
concrete task (action_required) with real stakes, in an active work track.
Sender/channel is NOT a gate — assignments and bills arrive from no-reply
systems just like noise does. These tests pin every branch of that rule,
including the regression where automated_system mail was wrongly filtered out.
"""

from types import SimpleNamespace

import pytest

from app.models import TrackKey
from app.services.classifier import EmailSignals
from app.services.sync import AUTO_TASK_TRACKS, should_auto_task


def signals(
    track: str = "uni",
    *,
    action_required: bool = True,
    sender_type: str = "professor",
    consequence: str = "grade_loss",
) -> EmailSignals:
    return EmailSignals(
        gmail_id="g1",
        track=track,
        sender_type=sender_type,
        consequence=consequence,
        action_required=action_required,
        confidence=0.9,
    )


def track_row(active: bool = True):
    return SimpleNamespace(active=active, weight=1.0)


# ── real tasks: SHOULD auto-task ────────────────────────────────────────────

def test_actionable_email_on_every_active_work_track_auto_tasks():
    for key in (TrackKey.uni, TrackKey.career, TrackKey.design, TrackKey.finance):
        assert should_auto_task(signals(key.value), key, track_row()) is True


@pytest.mark.parametrize(
    "track, sender_type, consequence, label",
    [
        ("uni", "automated_system", "grade_loss", "LMS assignment due"),
        ("career", "automated_system", "opportunity_loss", "ATS assessment link"),
        ("finance", "automated_system", "money_loss", "bank bill due"),
        ("design", "client", "client_trust", "client brief"),
        ("career", "recruiter", "opportunity_loss", "recruiter outreach"),
        ("uni", "professor", "grade_loss", "professor submission ask"),
    ],
)
def test_real_tasks_auto_task_regardless_of_sender(track, sender_type, consequence, label):
    s = signals(track, sender_type=sender_type, consequence=consequence)
    assert should_auto_task(s, TrackKey(track), track_row()) is True, label


def test_regression_automated_system_no_longer_blocks_assignment():
    """The exact bug: a uni assignment from a no-reply system must auto-task."""
    s = signals("uni", sender_type="automated_system", consequence="grade_loss")
    assert should_auto_task(s, TrackKey.uni, track_row()) is True


# ── noise: should NOT auto-task ─────────────────────────────────────────────

def test_no_action_required_stays_in_inbox():
    assert should_auto_task(signals(action_required=False), TrackKey.uni, track_row()) is False


def test_feed_never_auto_tasks():
    assert TrackKey.feed not in AUTO_TASK_TRACKS
    assert should_auto_task(signals("feed"), TrackKey.feed, track_row()) is False


def test_unclassified_track_stays_in_inbox():
    assert should_auto_task(signals("none"), None, None) is False


def test_dormant_track_stays_in_inbox():
    # design inactive (no freelance work in profile) → manual triage only
    assert should_auto_task(signals("design"), TrackKey.design, track_row(active=False)) is False


@pytest.mark.parametrize("consequence", ["social", "none"])
def test_no_stakes_mail_never_auto_tasks(consequence):
    # LinkedIn "add X" (social) or a zero-consequence FYI, even if the model
    # mislabels it action_required, is not real work worth scheduling.
    s = signals("career", sender_type="peer", consequence=consequence)
    assert should_auto_task(s, TrackKey.career, track_row()) is False
