"""More than one mailbox.

One Google account was baked into the user row, so college mail and personal
mail could not both reach Askcal. These pin the part that is easy to get wrong
once there are several: which mailbox answers which question.
"""

from types import SimpleNamespace

from app.services.accounts import (
    calendar_token,
    has_connected_mailbox,
    token_for_email,
)


def account(email: str, token: str | None = "t", primary: bool = False, active: bool = True):
    return SimpleNamespace(
        email=email, google_refresh_token=token, is_primary=primary, active=active
    )


def user(*accounts, legacy_token: str | None = None):
    return SimpleNamespace(mail_accounts=list(accounts), google_refresh_token=legacy_token)


# ── the calendar belongs to the sign-in account ────────────────────────────


def test_the_calendar_reads_the_primary_mailbox():
    u = user(account("uni@x", "uni-token"), account("me@x", "me-token", primary=True))
    assert calendar_token(u) == "me-token"


def test_an_account_with_no_rows_yet_falls_back_to_the_old_column():
    """A user row that predates mail_accounts must keep working untouched."""
    assert calendar_token(user(legacy_token="old")) == "old"


def test_no_mailbox_at_all_has_no_calendar():
    assert calendar_token(user()) is None


# ── acting on one message ──────────────────────────────────────────────────


def test_marking_read_uses_the_mailbox_the_mail_arrived_at():
    """The primary account's token marks nothing read for mail from a second
    inbox — that id does not exist over there — and fails silently."""
    uni = account("uni@x", "uni-token")
    u = user(uni, account("me@x", "me-token", primary=True))
    email = SimpleNamespace(account=uni)
    assert token_for_email(u, email) == "uni-token"


def test_mail_with_no_account_falls_back_to_the_primary():
    """Everything ingested before mail_accounts existed."""
    u = user(account("me@x", "me-token", primary=True))
    assert token_for_email(u, SimpleNamespace(account=None)) == "me-token"


# ── whether anything can be pulled ─────────────────────────────────────────


def test_a_second_live_inbox_still_counts_as_connected():
    """A revoked primary token must not read as "no Gmail connection" while a
    second mailbox is arriving perfectly well."""
    u = user(
        account("me@x", None, primary=True),
        account("uni@x", "uni-token"),
    )
    assert has_connected_mailbox(u)


def test_a_paused_mailbox_does_not_count():
    assert not has_connected_mailbox(user(account("uni@x", "t", active=False)))


def test_no_tokens_anywhere_is_not_connected():
    assert not has_connected_mailbox(user(account("uni@x", None)))
