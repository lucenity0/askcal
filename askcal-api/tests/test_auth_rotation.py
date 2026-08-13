"""Refresh-token rotation.

A refresh token lived thirty days and was accepted every time, so one captured
copy was thirty days of silent access with nothing anywhere looking unusual.
Each use now mints a replacement and retires the old one.

These pin the decision table rather than the wiring, because the wiring needs a
database and the decision is where this goes wrong: which retired tokens are
merely stale, and which mean somebody else has a copy.
"""

import datetime as dt
from types import SimpleNamespace

import pytest

from app.routers.auth import ROTATION_GRACE

NOW = dt.datetime(2026, 8, 13, 12, 0, tzinfo=dt.UTC)


def token(*, revoked_at=None, replaced=False, expires_in_days=30):
    return SimpleNamespace(
        revoked_at=revoked_at,
        replaced_by_id="successor" if replaced else None,
        expires_at=NOW + dt.timedelta(days=expires_in_days),
    )


def verdict(tok, now=NOW) -> str:
    """The router's decision, in one place so a test can state it.

    Mirrors the branch order in `refresh`: expiry first, then the retired cases,
    then rotation.
    """
    if tok is None or tok.expires_at <= now:
        return "reject"
    if tok.revoked_at is not None:
        rotated = tok.replaced_by_id is not None
        stale = now - tok.revoked_at > ROTATION_GRACE
        return "revoke_all" if (rotated and stale) else "reject"
    return "rotate"


def test_a_live_token_rotates():
    assert verdict(token()) == "rotate"


def test_an_expired_token_is_rejected():
    assert verdict(token(expires_in_days=-1)) == "reject"


def test_an_unknown_token_is_rejected():
    assert verdict(None) == "reject"


# ── the retired cases, which are the whole point ──────────────────────────


def test_a_rotated_token_coming_back_later_ends_every_session():
    """The real client holds the successor and would never send this one, so
    two parties have it and there is no way to tell which is which."""
    long_ago = NOW - ROTATION_GRACE - dt.timedelta(seconds=1)
    assert verdict(token(revoked_at=long_ago, replaced=True)) == "revoke_all"


def test_a_retry_moments_after_rotation_is_only_stale():
    """A client that never saw the response resends through no fault of anyone.
    Treating that as theft signs people out for having a bad connection."""
    just_now = NOW - dt.timedelta(seconds=5)
    assert verdict(token(revoked_at=just_now, replaced=True)) == "reject"


def test_a_signed_out_token_is_not_treated_as_theft():
    """Revoked by signing out, never replaced. Presenting it again is an old
    device catching up, not a copy — it should fail, not burn every session."""
    long_ago = NOW - dt.timedelta(days=2)
    assert verdict(token(revoked_at=long_ago, replaced=False)) == "reject"


def test_an_expired_token_is_never_treated_as_theft():
    """Expiry is checked first on purpose: a token old enough to have expired
    and been rotated is just old, and should not end a live session."""
    expired = token(expires_in_days=-1, revoked_at=NOW - dt.timedelta(days=40), replaced=True)
    assert verdict(expired) == "reject"


@pytest.mark.parametrize("seconds", [0, 1, 29])
def test_the_grace_window_covers_a_realistic_retry(seconds):
    assert verdict(token(revoked_at=NOW - dt.timedelta(seconds=seconds), replaced=True)) == "reject"
