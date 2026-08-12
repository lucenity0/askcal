"""Onboarding profile → track weights.

The onboarding questions ("what's your order?" student/working/both,
"what do you brew?" design/dev/both/other/none) map deterministically to
per-track weight + active settings. Weights feed the regret formula
(clamped 0.5–1.5 there), so two users receiving the identical email get
different scores when their lives differ.
"""

STUDENT_TYPES = {"student", "working", "both"}
WORK_TYPES = {"design", "dev", "both", "other", "none"}

_STUDIES = ("student", "both")
_FREELANCE_DESIGN = ("design", "both")


def profile_track_settings(
    student_type: str, work_type: str
) -> dict[str, tuple[float, bool]]:
    """→ {track slug: (weight, active)}.

    Rules:
    - career is always active; weighted up for placement-track users
      (students) and when there's no freelance work competing for it.
    - uni only exists if you study; weighted up when you do.
    - design activates only with freelance design work — otherwise dormant.
    - feed is always on, always background-weight.

    Keyed by slug, and only ever covers the five built-ins. Onboarding cannot
    have an opinion about a track the user invents afterwards, so anything not
    named here is left exactly as they set it — silently resetting someone's own
    track because they re-answered a questionnaire would be the same kind of
    invisible override this whole change exists to remove.
    """
    studies = student_type in _STUDIES
    designs = work_type in _FREELANCE_DESIGN

    return {
        "career": (1.2 if (studies and not designs) else 1.1 if studies else 1.0, True),
        "uni": ((1.2, True) if studies else (0.5, False)),
        "design": ((1.1, True) if designs else (0.5, False)),
        "feed": (0.8, True),
        # money is profile-independent: always on, neutral weight — urgency
        # comes from the regret formula's money_loss consequence, not here
        "finance": (1.0, True),
    }
