"""Regret score: deterministic 0–100 from classifier signals.

"Consequence of ignoring, not just arrival time" — the score is a transparent
formula over Gemini-extracted signals, so every score is reproducible from the
stored signals JSONB. When the trained ML model lands, it replaces this
module behind the same compute_regret() signature.

    score = (consequence base + deadline proximity + sender + action required)
            × track weight × confidence dampener, clamped to 0–100
"""

from datetime import datetime, timezone

from app.services.classifier import EmailSignals, parse_deadline

# What ignoring this email costs. The spec's examples anchor the scale:
# a client brief / OA / exam ignored ≈ costly; a newsletter ≈ nothing.
CONSEQUENCE_BASE = {
    "opportunity_loss": 35,  # missed OA, interview, placement window
    "grade_loss": 35,
    "client_trust": 35,
    "money_loss": 30,
    "social": 12,
    "none": 4,
}

# Proximity buckets in hours-until-deadline. Overdue (down to -72h) lands in
# the hottest bucket — "your espresso is getting cold" — then decays so stale
# overdue items don't pin the whole day at maximum forever.
DEADLINE_POINTS = [
    (24, 40),  # due within a day, or overdue up to 72h
    (48, 28),
    (96, 18),
    (168, 10),
]
DEADLINE_FAR_POINTS = 4  # beyond a week
DEADLINE_STALE_POINTS = 10  # overdue more than 72h
NO_DEADLINE_POINTS = 0

SENDER_POINTS = {
    "client": 12,
    "recruiter": 12,
    "professor": 8,
    "automated_system": 6,  # OA links arrive from noreply@
    "peer": 4,
    "newsletter": -20,
    "other": 0,
}

ACTION_REQUIRED_POINTS = 10

# Low-confidence classifications get dampened rather than trusted blindly.
LOW_CONFIDENCE_THRESHOLD = 0.4
LOW_CONFIDENCE_FACTOR = 0.6

TRACK_WEIGHT_MIN, TRACK_WEIGHT_MAX = 0.5, 1.5


def _deadline_points(deadline: datetime | None, now: datetime) -> int:
    if deadline is None:
        return NO_DEADLINE_POINTS
    hours_until = (deadline - now).total_seconds() / 3600
    if hours_until < -72:
        return DEADLINE_STALE_POINTS
    for bound, points in DEADLINE_POINTS:
        if hours_until <= bound:
            return points
    return DEADLINE_FAR_POINTS


def compute_regret(
    signals: EmailSignals,
    track_weight: float = 1.0,
    now: datetime | None = None,
) -> int:
    now = now or datetime.now(timezone.utc)

    score: float = (
        CONSEQUENCE_BASE[signals.consequence]
        + _deadline_points(parse_deadline(signals.deadline_utc), now)
        + SENDER_POINTS[signals.sender_type]
        + (ACTION_REQUIRED_POINTS if signals.action_required else 0)
    )

    weight = min(max(track_weight, TRACK_WEIGHT_MIN), TRACK_WEIGHT_MAX)
    score *= weight

    if signals.confidence < LOW_CONFIDENCE_THRESHOLD:
        score *= LOW_CONFIDENCE_FACTOR

    return max(0, min(100, round(score)))
