"""Sync orchestration.

`sync_user` is where the day's mail actually arrives, and it is where most of
this project's real bugs have lived: a mailbox that fails taking the others
with it, a timestamp that recorded only success so a failing sync looked
identical to one that had stopped, work that never got classified because an
earlier step raised.

The fetch and the classify pass are stubbed here. What is being tested is the
orchestration around them — which is the part that decides whether one broken
inbox costs you the day — and doing it with fakes keeps the suite free of a
database, which is what makes it worth running on every change.
"""

import asyncio
import datetime as dt
from types import SimpleNamespace

import pytest

from app.core.errors import AskcalError
from app.services import sync as sync_module
from app.services.sync import SyncResult, sync_user


class FakeSession:
    """Just enough AsyncSession for the orchestration to run.

    Counts rollbacks, because "did the failing mailbox leave the session usable
    for the next one" is the whole question in the failure path.
    """

    def __init__(self):
        self.commits = 0
        self.rollbacks = 0

    async def commit(self):
        self.commits += 1

    async def rollback(self):
        self.rollbacks += 1


def account(email: str):
    return SimpleNamespace(email=email, google_refresh_token="t", active=True)


def user(email: str = "me@x"):
    return SimpleNamespace(
        id="u1",
        email=email,
        timezone="Asia/Kolkata",
        last_sync_attempt_at=None,
        last_sync_error="left over from last time",
    )


@pytest.fixture
def wired(monkeypatch):
    """Stub the two halves and let the caller say how each behaves."""
    state = {"accounts": [], "fetch": {}, "classified": (0, 0), "fetched_for": []}

    async def fake_syncable(db, u):
        return state["accounts"]

    async def fake_store(db, u, acct):
        state["fetched_for"].append(acct.email)
        behaviour = state["fetch"].get(acct.email, SyncResult(fetched=3, new=1))
        if isinstance(behaviour, Exception):
            raise behaviour
        return behaviour

    async def fake_classify(db, u):
        return state["classified"]

    monkeypatch.setattr(sync_module, "syncable_accounts", fake_syncable)
    monkeypatch.setattr(sync_module, "_store_new_messages", fake_store)
    monkeypatch.setattr(sync_module, "_classify_pending", fake_classify)
    return state


def run(db, u):
    return asyncio.run(sync_user(db, u))


# ── the happy path ────────────────────────────────────────────────────────


def test_every_connected_mailbox_is_pulled(wired):
    wired["accounts"] = [account("me@x"), account("uni@x"), account("work@x")]
    db = FakeSession()

    result = run(db, user())

    assert wired["fetched_for"] == ["me@x", "uni@x", "work@x"]
    assert (result.fetched, result.new) == (9, 3)


def test_classification_runs_once_for_the_user_not_once_per_mailbox(wired):
    """A batch can span accounts, so the pass limit only means what it says if
    the pass is per-user."""
    wired["accounts"] = [account("a@x"), account("b@x")]
    wired["classified"] = (7, 2)

    result = run(FakeSession(), user())

    assert (result.classified, result.auto_tasked) == (7, 2)


def test_a_successful_pass_clears_a_stale_error(wired):
    wired["accounts"] = [account("me@x")]
    u = user()

    run(FakeSession(), u)

    assert u.last_sync_error is None


# ── the attempt is recorded before anything can fail ──────────────────────


def test_the_attempt_is_stamped_even_when_every_mailbox_fails(wired):
    """The reason this exists: `last_synced_at` only moved on success, so a sync
    running on time and failing was indistinguishable from one that had stopped
    running an hour ago."""
    wired["accounts"] = [account("me@x")]
    wired["fetch"] = {"me@x": RuntimeError("token revoked")}
    u = user()

    run(FakeSession(), u)

    assert u.last_sync_attempt_at is not None
    assert u.last_sync_attempt_at <= dt.datetime.now(dt.UTC)


def test_the_failure_names_the_mailbox_and_what_went_wrong(wired):
    wired["accounts"] = [account("uni@x")]
    wired["fetch"] = {"uni@x": RuntimeError("token revoked")}
    u = user()

    run(FakeSession(), u)

    assert "uni@x" in u.last_sync_error
    assert "RuntimeError" in u.last_sync_error


def test_a_very_long_failure_is_truncated_for_the_settings_row(wired):
    wired["accounts"] = [account("a" * 400 + "@x")]
    wired["fetch"] = {"a" * 400 + "@x": RuntimeError("boom")}
    u = user()

    run(FakeSession(), u)

    assert len(u.last_sync_error) <= 300


# ── one dead mailbox must not cost the others ─────────────────────────────


def test_a_failing_mailbox_does_not_stop_the_ones_after_it(wired):
    """A revoked token on a college address should cost that inbox, not the
    whole day."""
    wired["accounts"] = [account("dead@x"), account("live@x")]
    wired["fetch"] = {"dead@x": RuntimeError("revoked")}

    result = run(FakeSession(), user())

    assert wired["fetched_for"] == ["dead@x", "live@x"]
    assert (result.fetched, result.new) == (3, 1)


def test_a_failing_mailbox_rolls_back_so_the_session_still_works(wired):
    """Without the rollback the session stays in a failed transaction and every
    mailbox after it dies with PendingRollbackError — one bad inbox silently
    starving everything behind it."""
    wired["accounts"] = [account("dead@x"), account("live@x")]
    wired["fetch"] = {"dead@x": RuntimeError("revoked")}
    db = FakeSession()

    run(db, user())

    assert db.rollbacks == 1


def test_classification_still_runs_after_a_fetch_failure(wired):
    """Mail already sitting unclassified is not the broken mailbox's fault."""
    wired["accounts"] = [account("dead@x")]
    wired["fetch"] = {"dead@x": RuntimeError("revoked")}
    wired["classified"] = (4, 1)

    result = run(FakeSession(), user())

    assert (result.classified, result.auto_tasked) == (4, 1)


# ── nothing connected ─────────────────────────────────────────────────────


def test_no_mailbox_raises_and_says_so_on_the_user(wired):
    wired["accounts"] = []
    u = user()

    with pytest.raises(AskcalError) as caught:
        run(FakeSession(), u)

    assert caught.value.error == "GMAIL_DISCONNECTED"
    assert caught.value.code == 401
    assert u.last_sync_error == "No mailbox connected"
    # Still stamped: it ran, it just had nothing to pull.
    assert u.last_sync_attempt_at is not None


# ── one user must not starve the rest ─────────────────────────────────────


class FakeSessionFactory:
    """Stands in for `SessionLocal()` — an async context manager over one
    session, which is what the loop shares across every user in a pass."""

    def __init__(self, db, users):
        self.db = db
        self.users = users

    def __call__(self):
        return self

    async def __aenter__(self):
        self.db.scalars_result = self.users
        return self.db

    async def __aexit__(self, *exc):
        return False


class LoopSession(FakeSession):
    def __init__(self, users):
        super().__init__()
        self.users = users

    async def scalars(self, *_args, **_kwargs):
        return SimpleNamespace(all=lambda: self.users)

    async def get(self, _model, _pk):
        return self.users[0] if self.users else None


def test_one_user_failing_does_not_stop_the_pass(monkeypatch):
    """The rollback is the point. A user raising mid-transaction used to leave
    the shared session in a failed state, so everyone after them died with
    PendingRollbackError while the log read as though they were fine."""
    a, b, c = user("a@x"), user("b@x"), user("c@x")
    db = LoopSession([a, b, c])
    monkeypatch.setattr(sync_module, "SessionLocal", FakeSessionFactory(db, [a, b, c]))

    seen = []

    async def fake_sync_user(_db, u):
        seen.append(u.email)
        if u.email == "b@x":
            raise RuntimeError("revoked")
        return SyncResult()

    monkeypatch.setattr(sync_module, "sync_user", fake_sync_user)
    asyncio.run(sync_module.sync_all_users())

    assert seen == ["a@x", "b@x", "c@x"]
    assert db.rollbacks == 1
    assert "revoked" in b.last_sync_error


def test_the_background_entrypoint_never_raises(monkeypatch):
    """It is handed to FastAPI's background tasks, where an exception is
    unhandled and invisible."""
    u = user()
    db = LoopSession([u])
    monkeypatch.setattr(sync_module, "SessionLocal", FakeSessionFactory(db, [u]))

    async def boom(_db, _u):
        raise RuntimeError("nope")

    monkeypatch.setattr(sync_module, "sync_user", boom)
    asyncio.run(sync_module.run_sync_for_user("u1"))  # must not raise
