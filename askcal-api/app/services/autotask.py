"""Whether a classified email becomes a task, and how that task is built.

Extracted so the two paths that create email-derived tasks — the sync pipeline
and the manual swipe in routers/inbox.py — share one implementation. They had
already drifted apart (one read the typed EmailSignals, the other read the JSONB
dict), which meant every gate added to one silently missed the other.

The gating story: the original rule was
    action_required AND consequence not in {social, none} AND active work track
which is effectively "the model said yes". Three of its five clauses are almost
always true for a default user, and the two-element consequence blacklist is
bypassed by exactly the noisiest mail — a blast only has to be labelled
money_loss or opportunity_loss ("your payment failed", "offer expires tonight")
to pass. Meanwhile confidence and regret_score were both already computed and
never consulted. They are now floors.
"""

import logging
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import Email, Task, TaskStatus, Track, TrackKey
from app.services.classifier import parse_deadline

logger = logging.getLogger("askcal.autotask")

# Tracks whose actionable mail turns into tasks automatically. `feed` is
# read-later by definition and never auto-tasks.
AUTO_TASK_TRACKS = {TrackKey.career, TrackKey.design, TrackKey.uni, TrackKey.finance}

# A real task always has real stakes: social notifications ("add X", "someone
# viewed you") and zero-consequence FYIs are never work, even when the model
# marks them action_required.
#
# sender_type is deliberately NOT a gate. Legitimate tasks — assignment due,
# online assessment, bill payable — arrive from no-reply/automated systems
# exactly like noise does; filtering automated_system out silently drops real
# work (the original assignment-not-tasking bug, c31d94b).
NON_TASKING_CONSEQUENCES = {"social", "none"}


def sanitize_deadline(
    raw: str | None, received_at: datetime, *, now: datetime | None = None
) -> datetime | None:
    """Parse a model-supplied deadline, rejecting implausible ones.

    parse_deadline only checks that the string is ISO-parseable, so a
    hallucinated year used to land straight in due_at — and because the regret
    formula buckets anything within 24 hours (including negatives) at its
    highest deadline score, a garbage past date read as maximally urgent forever.
    """
    parsed = parse_deadline(raw)
    if parsed is None:
        return None
    s = get_settings()
    if received_at.tzinfo is None:
        received_at = received_at.replace(tzinfo=timezone.utc)

    horizon = received_at + timedelta(days=s.deadline_max_horizon_days)
    floor = received_at - timedelta(days=s.deadline_max_overdue_days)
    if parsed > horizon or parsed < floor:
        logger.warning(
            "dropping implausible deadline %s (email received %s)",
            parsed.isoformat(),
            received_at.isoformat(),
        )
        return None
    return parsed


def scheduled_day_for(due_at: datetime | None, today: date) -> date:
    """The day this task belongs on.

    Everything used to land on today unconditionally, so a deadline three weeks
    out still inflated today's plan and the carry-forward count. Now a task
    surfaces `task_schedule_lead_days` before it is due — and never in the past,
    because an overdue item belongs on today's list, not on the day it was
    missed.
    """
    if due_at is None:
        return today
    lead = timedelta(days=get_settings().task_schedule_lead_days)
    return max(today, (due_at.astimezone(timezone.utc).date() - lead))


def auto_task_gates(user) -> tuple[float, int]:
    """The two thresholds, for this user.

    Falls back to the deployment defaults when they have never been set, so a
    fresh account behaves exactly as the server was configured to and only
    diverges once someone deliberately moves a dial.
    """
    s = get_settings()
    prefs = getattr(user, "preferences", None) or {}
    return (
        prefs.get("auto_task_min_confidence", s.auto_task_min_confidence),
        prefs.get("auto_task_min_regret", s.auto_task_min_regret),
    )


def should_auto_task(
    signals,
    track: TrackKey | None,
    track_row: Track | None,
    regret_score: int | None = None,
    user=None,
) -> bool:
    """A mail auto-tasks when the model says the user must personally do a
    concrete task (action_required) with a real consequence, in a real
    (non-feed) work track that's active for this user — and when the model was
    actually confident and the stakes actually scored.

    Channel/sender is not a gate: an assignment from a no-reply LMS is as real
    as a client email.

    regret_score is optional so the predicate stays callable without a scored
    email; when omitted the regret floor is simply not applied.

    `user` supplies the thresholds. Omitting it uses the deployment defaults,
    which keeps every existing test and caller working unchanged.
    """
    min_confidence, min_regret = auto_task_gates(user)
    if not (
        signals.action_required
        and signals.consequence not in NON_TASKING_CONSEQUENCES
        and track in AUTO_TASK_TRACKS
        and track_row is not None
        and track_row.active
    ):
        return False
    if signals.confidence < min_confidence:
        return False
    if regret_score is not None and regret_score < min_regret:
        return False
    return True


def build_task(
    email: Email,
    deadline_utc: str | None,
    track_row: Track,
    today: date,
) -> Task:
    """The daily-pipeline payoff: an actionable classified email becomes a task.

    The single constructor for email-derived tasks — used by both the sync
    pipeline and the manual swipe, so a gate can only be added in one place.
    """
    due_at = sanitize_deadline(deadline_utc, email.received_at)
    return Task(
        user_id=email.user_id,
        track_id=track_row.id,
        source_email_id=email.id,
        title=email.subject or (email.snippet or "untitled")[:200],
        regret_score=email.regret_score or 0,
        estimated_hours=(
            round(email.estimated_minutes / 60, 1) if email.estimated_minutes else None
        ),
        due_at=due_at,
        scheduled_for=scheduled_day_for(due_at, today),
    )


async def open_task_exists_for_thread(db: AsyncSession, email: Email) -> bool:
    """Is there already an open task from this email's conversation?

    Email.thread_id has been stored and indexed all along but was never read, so
    three reminders about one assignment ("due Friday" / "due in 2 days" /
    "final reminder") became three separate tasks, as did every reply on a
    client brief.

    Scoped to non-done tasks on purpose: finishing a task and then getting a
    genuinely new request on the same thread should produce a new task.
    """
    if not email.thread_id:
        return False
    found = await db.scalar(
        select(Task.id)
        .join(Email, Task.source_email_id == Email.id)
        .where(
            Task.user_id == email.user_id,
            Task.status != TaskStatus.done,
            Email.thread_id == email.thread_id,
        )
        .limit(1)
    )
    return found is not None
