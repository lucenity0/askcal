"""Which band a piece of mail lands in.

The inbox is grouped by what mail wants from you, and these bands decide what a
student sees first thing in the morning. Getting "nothing to do" wrong is the
expensive direction: it buries work.
"""

import datetime as dt

from app.services.triage import mail_need

NOW = dt.datetime(2026, 8, 12, 9, 0, tzinfo=dt.timezone.utc)


def signals(**over):
    base = {
        "action_required": False,
        "sender_type": "other",
        "consequence": "none",
        "deadline_utc": None,
    }
    base.update(over)
    return base


def test_unclassified_mail_is_read_not_noise():
    """With the classifier down, everything is unclassified — filing it all as
    noise would bury the entire inbox on the strength of no information."""
    assert mail_need(None, NOW) == "read"
    assert mail_need({}, NOW) == "read"


def test_a_person_expecting_an_answer_needs_a_reply():
    for sender in ("professor", "client", "recruiter", "peer"):
        s = signals(action_required=True, sender_type=sender, consequence="social")
        assert mail_need(s, NOW) == "reply", sender


def test_an_automated_sender_creates_work_but_not_a_reply():
    """An LMS notice is real work; it is not sitting there waiting for you to
    write back."""
    s = signals(action_required=True, sender_type="automated_system",
                consequence="grade_loss")
    assert mail_need(s, NOW) == "deadline"


def test_a_future_deadline_wins_over_everything():
    s = signals(action_required=True, sender_type="professor",
                deadline_utc="2026-08-14T17:00:00Z")
    assert mail_need(s, NOW) == "deadline"


def test_a_deadline_already_passed_is_not_a_deadline():
    """Otherwise the band fills with things that can no longer be acted on."""
    s = signals(deadline_utc="2026-08-01T17:00:00Z", consequence="grade_loss")
    assert mail_need(s, NOW) == "read"


def test_a_malformed_deadline_does_not_crash_the_inbox():
    for bad in ("soon", "", "2026-13-45"):
        assert mail_need(signals(deadline_utc=bad), NOW) in {"read", "none"}


def test_a_naive_deadline_is_treated_as_utc():
    s = signals(deadline_utc="2026-08-14T17:00:00")
    assert mail_need(s, NOW) == "deadline"


def test_nothing_at_stake_is_noise():
    s = signals(sender_type="newsletter", consequence="none")
    assert mail_need(s, NOW) == "none"


def test_something_at_stake_is_worth_a_look_even_with_no_action():
    s = signals(sender_type="automated_system", consequence="money_loss")
    assert mail_need(s, NOW) == "read"
