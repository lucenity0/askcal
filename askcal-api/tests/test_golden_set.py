"""What a correct classification then does.

The corpus in `golden_set.py` says how each mail should be read. These tests do
not run a model — they take that reading as given and pin what happens next:
whether it becomes work, and which band of the inbox it lands in.

That is the half worth having in the normal suite. A prompt regression needs the
real classifier to catch (see `app/scripts/classify_golden.py`), but a gate
regression — the thing that decides whether a newsletter becomes a task on your
Tuesday — is pure logic and should never have needed a model to notice.
"""

from types import SimpleNamespace

import pytest

from app.services.autotask import should_auto_task
from app.services.classifier import EmailSignals
from app.services.tracks import BUILTIN_TRACKS
from app.services.triage import mail_need
from tests.golden_set import GOLDEN

BUILTIN_SLUGS = {spec["slug"] for spec in BUILTIN_TRACKS}


def signals_for(case) -> EmailSignals:
    return EmailSignals(
        gmail_id=case.id,
        track=case.track,
        sender_type="automated_system",
        consequence=case.consequence,
        action_required=case.action_required,
        deadline_utc="2026-08-20T17:00:00Z" if case.has_deadline else None,
        confidence=0.9,
    )


def track_row(auto_tasks: bool = True):
    return SimpleNamespace(active=True, weight=1.0, auto_tasks=auto_tasks)


def test_the_corpus_is_internally_coherent():
    """A case that names a track nothing ships with, or claims a deadline it
    never wrote, is a broken test rather than a finding."""
    for case in GOLDEN:
        # "none" is a real answer, not a track: mail that belongs nowhere.
        assert case.track in BUILTIN_SLUGS | {"none"}, f"{case.id}: unknown track"
        assert case.why.strip(), f"{case.id}: no reason to exist"
        if case.action_required:
            assert case.consequence != "none", f"{case.id}: work with no stakes"


@pytest.mark.parametrize("case", [c for c in GOLDEN if c.action_required], ids=lambda c: c.id)
def test_real_work_survives_the_gates(case):
    """Everything the corpus calls work must actually become work.

    The gates exist to stop over-creation, and every floor added to them is a
    chance to silently drop the assignment that mattered — which has happened.
    """
    assert should_auto_task(signals_for(case), track_row(), 70) is True


@pytest.mark.parametrize("case", [c for c in GOLDEN if not c.action_required], ids=lambda c: c.id)
def test_noise_never_becomes_work(case):
    assert should_auto_task(signals_for(case), track_row(), 70) is False


@pytest.mark.parametrize("case", GOLDEN, ids=lambda c: c.id)
def test_a_read_later_track_never_makes_work(case):
    """Whatever the mail is, a track set to make no work makes none. Covers the
    mailbox marked read-only as well as the `feed` default."""
    assert should_auto_task(signals_for(case), track_row(auto_tasks=False), 70) is False


@pytest.mark.parametrize("case", GOLDEN, ids=lambda c: c.id)
def test_the_inbox_band_follows_from_the_same_signals(case):
    """The band the app groups by is derived from the stored signals, so the
    inbox and the auto-tasker cannot end up disagreeing about what a mail is.

    Work lands in a band that asks something of you — `deadline` or `reply`.
    `deadline` covers actionable mail with no date attached, which is deliberate:
    the band means "something to do", and demoting it to `read` because nobody
    named a day is how a real task ends up filed as light reading.
    """
    need = mail_need(signals_for(case).model_dump())
    if case.action_required:
        assert need in {"deadline", "reply"}, f"{case.id}: work landed in {need}"
    else:
        assert need in {"read", "none"}, f"{case.id}: noise landed in {need}"


def test_the_two_money_mails_are_not_the_same_mail():
    """A fee that is due and a receipt for the same amount differ by one word,
    and only one of them is work. If the corpus ever lets them collapse, the
    case that catches the real regression has stopped catching anything."""
    due = next(c for c in GOLDEN if c.id == "fees-due")
    paid = next(c for c in GOLDEN if c.id == "payment-receipt")

    assert due.action_required and not paid.action_required
    assert should_auto_task(signals_for(due), track_row(), 70)
    assert not should_auto_task(signals_for(paid), track_row(), 70)
