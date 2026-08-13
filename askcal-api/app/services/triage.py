"""What a piece of mail actually wants from you.

The inbox used to be ordered by regret score alone, which is a real ranking and
an invisible one: every row looks the same, so you read all of them. The only
question you are actually asking while triaging is "does this need something
from me, and by when" — so that is what the inbox is grouped by.

Nothing new is asked of the model. `action_required`, `sender_type` and
`deadline_utc` are already extracted per email and stored as JSONB on the row;
this reads them. That matters: adding a field would mean a prompt change and
re-classifying every email already in the database, and would make the grouping
disagree with the auto-tasker, which reads the same signals.
"""

import datetime as dt
from typing import Literal

__all__ = ["MailNeed", "mail_need"]

MailNeed = Literal["reply", "deadline", "read", "none"]

# Senders who are a person waiting on an answer. An automated system or a
# newsletter can create work, but it is not sitting there expecting a reply.
_HUMAN_SENDERS = {"professor", "client", "recruiter", "peer"}


def mail_need(signals: dict | None, now: dt.datetime | None = None) -> MailNeed:
    """Which band this mail belongs in.

    Unclassified mail is `read`, never `none`. Nobody has looked at it yet, and
    filing it as noise on the strength of no information buries exactly the mail
    that most needs a human glance — which is what the whole inbox looks like
    whenever the classifier is down.
    """
    if not signals:
        return "read"

    if _has_live_deadline(signals.get("deadline_utc"), now):
        return "deadline"

    action = bool(signals.get("action_required"))
    if action and signals.get("sender_type") in _HUMAN_SENDERS:
        return "reply"
    if action:
        return "deadline"  # something to do, no date attached to it

    # No action wanted. Only mail with nothing at stake is noise; the rest is
    # worth a look when there is time.
    return "none" if signals.get("consequence") in (None, "none") else "read"


def _has_live_deadline(raw: str | None, now: dt.datetime | None) -> bool:
    """A deadline counts only if it is real and still ahead.

    A date that has already passed is not a deadline any more, and leaving it in
    that band means the group fills up with things you can no longer act on.
    """
    if not raw:
        return False
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return False
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed > (now or dt.datetime.now(dt.UTC))
