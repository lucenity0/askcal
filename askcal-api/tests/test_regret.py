"""Regret formula tests. Every score must be reproducible from signals alone."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from app.services.classifier import EmailSignals
from app.services.regret import compute_regret

NOW = datetime(2026, 7, 4, 12, 0, tzinfo=UTC)


def make_signals(**overrides) -> EmailSignals:
    base = {
        "gmail_id": "x",
        "track": "career",
        "sender_type": "other",
        "consequence": "none",
        "action_required": False,
        "deadline_utc": None,
        "estimated_minutes": None,
        "confidence": 0.9,
    }
    base.update(overrides)
    return EmailSignals(**base)


def iso_in(hours: float) -> str:
    return (NOW + timedelta(hours=hours)).isoformat()


def test_amazon_oa_email_scores_high():
    # opportunity_loss 35 + deadline 48h 28 + automated 6 + action 10 = 79
    signals = make_signals(
        track="career",
        sender_type="automated_system",
        consequence="opportunity_loss",
        action_required=True,
        deadline_utc=iso_in(48),
    )
    assert compute_regret(signals, now=NOW) == 79


def test_client_brief_due_tomorrow_is_extreme():
    # client_trust 35 + deadline 24h 40 + client 12 + action 10 = 97
    signals = make_signals(
        track="design",
        sender_type="client",
        consequence="client_trust",
        action_required=True,
        deadline_utc=iso_in(20),
    )
    assert compute_regret(signals, now=NOW) == 97


def test_newsletter_scores_zero():
    # none 4 + no deadline 0 + newsletter -20 = -16 → clamp 0
    signals = make_signals(
        track="feed", sender_type="newsletter", consequence="none"
    )
    assert compute_regret(signals, now=NOW) == 0


def test_assignment_due_in_six_days():
    # grade_loss 35 + 144h→(≤168) 10 + professor 8 + action 10 = 63
    signals = make_signals(
        track="uni",
        sender_type="professor",
        consequence="grade_loss",
        action_required=True,
        deadline_utc=iso_in(144),
    )
    assert compute_regret(signals, now=NOW) == 63


def test_overdue_within_72h_stays_hot():
    # grade_loss 35 + overdue(-24h) 40 + professor 8 + action 10 = 93
    signals = make_signals(
        sender_type="professor",
        consequence="grade_loss",
        action_required=True,
        deadline_utc=iso_in(-24),
    )
    assert compute_regret(signals, now=NOW) == 93


def test_stale_overdue_decays():
    # grade_loss 35 + stale overdue 10 + professor 8 + action 10 = 63
    signals = make_signals(
        sender_type="professor",
        consequence="grade_loss",
        action_required=True,
        deadline_utc=iso_in(-100),
    )
    assert compute_regret(signals, now=NOW) == 63


def test_far_deadline_gets_minimal_points():
    # opportunity_loss 35 + far 4 + recruiter 12 + action 10 = 61
    signals = make_signals(
        sender_type="recruiter",
        consequence="opportunity_loss",
        action_required=True,
        deadline_utc=iso_in(24 * 14),
    )
    assert compute_regret(signals, now=NOW) == 61


def test_track_weight_scales_and_clamps():
    signals = make_signals(
        sender_type="client",
        consequence="client_trust",
        action_required=True,
        deadline_utc=iso_in(20),
    )  # raw 97
    assert compute_regret(signals, track_weight=0.5, now=NOW) == 48
    assert compute_regret(signals, track_weight=1.5, now=NOW) == 100  # clamped
    # weights outside [0.5, 1.5] are clamped before applying
    assert compute_regret(signals, track_weight=99.0, now=NOW) == 100
    assert compute_regret(signals, track_weight=0.01, now=NOW) == 48


def test_low_confidence_dampens():
    signals = make_signals(
        sender_type="client",
        consequence="client_trust",
        action_required=True,
        deadline_utc=iso_in(20),
        confidence=0.3,
    )  # raw 97 * 0.6 = 58.2 → 58
    assert compute_regret(signals, now=NOW) == 58


def test_unparseable_deadline_treated_as_none():
    signals = make_signals(consequence="grade_loss", deadline_utc="next tuesday-ish")
    # grade_loss 35 + 0 + other 0 + no action 0 = 35
    assert compute_regret(signals, now=NOW) == 35


@pytest.mark.parametrize("consequence", ["opportunity_loss", "grade_loss", "client_trust"])
def test_score_always_in_range(consequence):
    signals = make_signals(
        sender_type="client",
        consequence=consequence,
        action_required=True,
        deadline_utc=iso_in(1),
    )
    assert 0 <= compute_regret(signals, track_weight=1.5, now=NOW) <= 100


# ── what skipping something has already cost ──────────────────────────────


def carried(times: int, score: int = 40):
    return SimpleNamespace(regret_score=score, carried_count=times)


def test_fresh_work_scores_exactly_what_the_classifier_said():
    from app.services.regret import effective_regret

    assert effective_regret(carried(0)) == 40


def test_each_carry_forward_adds_to_the_argument():
    """A task pushed four times ranked exactly as it did on day one and kept
    losing to whatever was newest — which is how the thing you are avoiding
    stays avoided."""
    from app.services.regret import effective_regret

    assert effective_regret(carried(1)) > effective_regret(carried(0))
    assert effective_regret(carried(4)) > effective_regret(carried(1))


def test_zero_sensitivity_leaves_the_classifier_alone():
    """The dial's floor is "do not do this at all", not "do a little of it"."""
    from app.services.regret import effective_regret

    assert effective_regret(carried(5), 0.0) == 40


def test_sensitivity_scales_the_push():
    from app.services.regret import effective_regret

    gentle = effective_regret(carried(3), 0.5)
    firm = effective_regret(carried(3), 2.0)
    assert 40 < gentle < firm


def test_it_cannot_climb_past_the_top_of_the_scale():
    """The score is 0–100 everywhere else; carried work must not invent a 130
    that outranks a genuine emergency by an amount the scale cannot express."""
    from app.services.regret import effective_regret

    assert effective_regret(carried(40, score=95), 3.0) == 100


def test_a_task_with_no_carry_count_at_all_is_handled():
    from app.services.regret import effective_regret

    assert effective_regret(SimpleNamespace(regret_score=30)) == 30
