"""Profile → weights → regret: two different lives, same email, different scores."""

from app.services.classifier import EmailSignals
from app.services.profile import profile_track_settings
from app.services.regret import compute_regret


def design_brief_signals() -> EmailSignals:
    return EmailSignals(
        gmail_id="x",
        track="design",
        sender_type="client",
        consequence="client_trust",
        action_required=True,
        deadline_utc=None,
        estimated_minutes=60,
        confidence=0.9,
    )


def test_student_no_freelance_dims_design_boosts_career_uni():
    settings = profile_track_settings("student", "none")
    assert settings["design"] == (0.5, False)  # dormant
    assert settings["career"][0] > 1.0
    assert settings["uni"] == (1.2, True)


def test_freelance_designer_activates_design():
    settings = profile_track_settings("both", "design")
    weight, active = settings["design"]
    assert active and weight > 1.0


def test_identical_email_scores_differently_across_profiles():
    signals = design_brief_signals()

    # profile A: pure student, no freelance → design dormant at 0.5
    weight_a = profile_track_settings("student", "none")["design"][0]
    # profile B: student + freelance design → design boosted
    weight_b = profile_track_settings("student", "design")["design"][0]

    score_a = compute_regret(signals, track_weight=weight_a)
    score_b = compute_regret(signals, track_weight=weight_b)

    assert score_a != score_b
    assert score_b > score_a  # the freelancer regrets ignoring the client more


def test_career_always_active():
    for student in ("student", "working", "both"):
        for work in ("design", "none", "dev"):
            assert profile_track_settings(student, work)["career"][1] is True


def test_finance_always_active_neutral_weight():
    # finance is profile-independent: urgency comes from the money_loss
    # consequence in the regret formula, not from the profile weight
    for student in ("student", "working", "both"):
        for work in ("design", "none", "dev"):
            assert profile_track_settings(student, work)["finance"] == (1.0, True)
