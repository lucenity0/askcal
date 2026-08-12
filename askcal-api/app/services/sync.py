"""Sync orchestration: Gmail fetch → store raw → classify → regret score
→ auto-create tasks.

Runs two ways, per the phase-2 decision:
- background: sync_loop() started from the app lifespan, every
  ASKCAL_SYNC_INTERVAL_MINUTES
- on demand: POST /api/inbox/sync schedules run_sync_for_user() as a
  background task

Classification never blocks ingestion — new mail lands in the emails table
immediately; unclassified rows are picked up here (and retried) in batches.

The fetch is scoped to the user's current local day, so a re-sync re-checks
today's mail only; the gmail_id unique constraint keeps it duplicate-free.

Auto-task rule (owner decision): an email becomes a task the moment it's
classified IF the model says action_required AND its track is real work
(not feed) AND that track is active for this user. Auto-tasked emails are
marked handled — the inbox only ever shows what still needs a human.
"""

import asyncio
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.errors import AskcalError
from app.db import SessionLocal
from app.llm.base import LLMLimitError
from app.models import Email, MailAccount, Track, User
from app.services.autotask import (
    NON_TASKING_CONSEQUENCES,
    build_task,
    open_task_exists_for_thread,
    should_auto_task,
)
from app.services.classifier import (
    classifier_configured,
    classify_batch,
    classify_pacing,
)
from app.services.tracks import track_by_slug
from app.services.gmail import fetch_recent_messages
from app.services.regret import compute_regret
from app.services.scheduling import local_midnight, user_today

logger = logging.getLogger("askcal.sync")

# Re-exported: the gating rule lives in autotask.py (shared with the manual
# swipe path) but has always been imported from here.
__all__ = [
    "NON_TASKING_CONSEQUENCES",
    "CLASSIFY_PASS_LIMIT",
    "SyncResult",
    "run_sync_for_user",
    "should_auto_task",
    "sync_all_users",
    "sync_loop",
    "sync_user",
]

CLASSIFY_PASS_LIMIT = 50  # max unclassified emails handled per sync pass


@dataclass
class SyncResult:
    fetched: int = 0
    new: int = 0
    classified: int = 0
    auto_tasked: int = 0


async def _store_new_messages(
    db: AsyncSession, user: User, account: MailAccount
) -> SyncResult:
    """Pull one mailbox.

    Dedup is still on (user_id, gmail_id) rather than (account_id, gmail_id).
    Gmail ids are per-mailbox, so the same message in two accounts carries two
    different ids and both are stored — a collision across mailboxes would have
    to be an id reused between accounts, which Gmail does not do.
    """
    result = SyncResult()
    messages = await fetch_recent_messages(
        account.google_refresh_token, since=local_midnight(user.timezone)
    )
    result.fetched = len(messages)
    if messages:
        existing = set(
            (
                await db.scalars(
                    select(Email.gmail_id).where(
                        Email.user_id == user.id,
                        Email.gmail_id.in_([m.gmail_id for m in messages]),
                    )
                )
            ).all()
        )
        for m in messages:
            if m.gmail_id in existing:
                continue
            db.add(
                Email(
                    user_id=user.id,
                    gmail_id=m.gmail_id,
                    thread_id=m.thread_id,
                    account_email=account.email,
                    account_id=account.id,
                    subject=m.subject,
                    sender=m.sender,
                    snippet=m.snippet,
                    body_text=m.body_text,
                    received_at=m.received_at,
                    raw=m.raw,
                )
            )
            result.new += 1
    now = datetime.now(timezone.utc)
    account.last_synced_at = now
    user.last_synced_at = now
    await db.commit()
    return result


async def _classify_pending(db: AsyncSession, user: User) -> tuple[int, int]:
    """→ (classified count, auto-created task count)."""
    # Guards the SELECT below, not just the LLM call: with no provider there is
    # no point querying pending mail every sync interval.
    if not classifier_configured():
        return 0, 0

    s = get_settings()
    # Pass-level shortlist, deliberately UNLOCKED. Locks taken here would be
    # released by the first chunk's commit anyway — a transaction cannot hold
    # row locks past its own end — so locking the whole pass would protect only
    # chunk 1 while reading as though it protected all of them. The claim
    # happens per chunk, below.
    pending_ids = (
        await db.scalars(
            select(Email.id)
            .where(
                Email.user_id == user.id,
                Email.classified_at.is_(None),
                # Give up on mail that keeps failing. Without this a message the
                # model can never parse sits at the head of this queue forever,
                # is re-sent every sync interval, and — at LIMIT 50 — crowds out
                # real work while burning quota indefinitely.
                Email.classify_attempts < s.classify_max_attempts,
            )
            .order_by(Email.received_at.desc())
            .limit(CLASSIFY_PASS_LIMIT)
        )
    ).all()
    if not pending_ids:
        return 0, 0

    # The list, not a lookup by enum key: the classifier is told about these by
    # name and answers with one of their slugs, so the same rows have to build
    # the prompt and resolve the reply.
    tracks = list(
        (await db.scalars(select(Track).where(Track.user_id == user.id))).all()
    )

    classified = 0
    auto_tasked = 0
    now = datetime.now(timezone.utc)
    today = user_today(user.timezone)
    tasked_threads: set[str] = set()
    batch_size, delay = classify_pacing()
    for start in range(0, len(pending_ids), batch_size):
        id_slice = pending_ids[start : start + batch_size]
        if start > 0 and delay:
            await asyncio.sleep(delay)

        # Claim this chunk inside the transaction that will process it, so the
        # lock actually spans the LLM call it is protecting. SKIP LOCKED means a
        # concurrent pass — the background loop racing an on-demand
        # POST /api/inbox/sync, i.e. the user pulling to refresh mid-batch —
        # takes different rows instead of duplicating this call. Re-checking
        # classified_at catches rows a concurrent pass finished and committed
        # after the shortlist above was taken.
        chunk = list(
            (
                await db.scalars(
                    select(Email)
                    .where(Email.id.in_(id_slice), Email.classified_at.is_(None))
                    .with_for_update(skip_locked=True)
                )
            ).all()
        )
        if not chunk:
            continue

        try:
            signals_by_id = await classify_batch(chunk, user.timezone, tracks)
        except LLMLimitError:
            # Out of allowance, not broken. Grinding the remaining chunks against
            # the wall just burns retries against a limit that only time fixes.
            logger.warning("LLM quota reached — stopping this pass, resuming next sync")
            break
        except Exception:
            # Deliberately NOT counted against classify_attempts. This catches
            # transport failures — a wedged CLI, a subprocess crash, a network
            # blip — which say nothing about whether the mail is classifiable.
            # Charging them would let three unlucky passes permanently and
            # silently drop 25 emails from the queue, recoverable only by hand
            # in SQL. The attempt counter exists for mail the model cannot
            # parse, and that case is counted per-email below.
            logger.exception("classification call failed; will retry next sync")
            await db.rollback()
            continue
        for email in chunk:
            signals = signals_by_id.get(email.gmail_id)
            if signals is None:
                # Omitted or mangled. Counted so a message the model can never
                # produce valid signals for eventually stops being retried.
                email.classify_attempts += 1
                continue
            track_row = track_by_slug(tracks, signals.track)
            email.track_id = track_row.id if track_row else None
            # The old enum column, still written so a rollback has its data.
            # None for a track the user invented — there is no enum member to
            # put there, which is the whole reason the column is going.
            email.track = track_row.key if track_row else None
            email.estimated_minutes = signals.estimated_minutes
            email.signals = signals.model_dump()
            email.regret_score = compute_regret(
                signals,
                track_weight=track_row.weight if track_row else 1.0,
                now=now,
            )
            email.classified_at = now
            classified += 1

            if not should_auto_task(signals, track_row, email.regret_score, user):
                continue
            # Thread dedup. Checked against both the database and this pass,
            # because tasks added below are not flushed until the chunk commits —
            # two reminders about the same assignment can easily land in one batch.
            if email.thread_id and email.thread_id in tasked_threads:
                continue
            if await open_task_exists_for_thread(db, email):
                logger.info(
                    "skipping auto-task for %s — open task already exists on thread %s",
                    email.gmail_id,
                    email.thread_id,
                )
                continue
            # Savepoint per task, so losing the duplicate race costs one task
            # rather than the chunk. Without it the failing INSERT surfaces at
            # the chunk commit below, taking every classified_at/signals update
            # in the chunk down with it — the emails would be re-classified from
            # scratch next pass, paying for the same LLM call twice.
            try:
                async with db.begin_nested():
                    db.add(build_task(email, signals.deadline_utc, track_row, today))
            except IntegrityError:
                logger.info(
                    "task already exists for %s — a concurrent pass won the race",
                    email.gmail_id,
                )
                email.handled = True
                continue
            if email.thread_id:
                tasked_threads.add(email.thread_id)
            email.handled = True
            auto_tasked += 1
        await db.commit()
    return classified, auto_tasked


async def syncable_accounts(db: AsyncSession, user: User) -> list[MailAccount]:
    """The mailboxes worth pulling: connected and not paused."""
    rows = (
        await db.scalars(
            select(MailAccount).where(
                MailAccount.user_id == user.id,
                MailAccount.active.is_(True),
                MailAccount.google_refresh_token.is_not(None),
            )
        )
    ).all()
    return list(rows)


async def sync_user(db: AsyncSession, user: User) -> SyncResult:
    """Full pass for one user, across every mailbox they have connected.

    Raises GMAIL_DISCONNECTED only when there is nothing to pull at all.
    """
    accounts = await syncable_accounts(db, user)
    if not accounts:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "No Gmail connection for this account")

    result = SyncResult()
    for account in accounts:
        try:
            fetched = await _store_new_messages(db, user, account)
        except Exception:
            # One dead mailbox must not stop the others. A revoked token on a
            # college address should cost you that inbox, not your whole day.
            await db.rollback()
            logger.exception("fetch failed for %s — continuing", account.email)
            continue
        result.fetched += fetched.fetched
        result.new += fetched.new

    # Classification is per-user, not per-mailbox: it runs over everything
    # unclassified in one pass, so a batch can span accounts and the pass limit
    # still means what it says.
    result.classified, result.auto_tasked = await _classify_pending(db, user)
    logger.info(
        "sync %s (%d mailbox%s): fetched=%d new=%d classified=%d auto_tasked=%d",
        user.email, len(accounts), "" if len(accounts) == 1 else "es",
        result.fetched, result.new, result.classified, result.auto_tasked,
    )
    return result


async def run_sync_for_user(user_id: uuid.UUID) -> None:
    """Background-task entrypoint — owns its session, never raises."""
    try:
        async with SessionLocal() as db:
            user = await db.get(User, user_id)
            if user is None:
                return
            await sync_user(db, user)
    except Exception:
        logger.exception("on-demand sync failed for user %s", user_id)


async def sync_all_users() -> None:
    async with SessionLocal() as db:
        # Anyone with at least one live mailbox. Keyed off the accounts now, so a
        # user whose primary is disconnected but whose second inbox still works
        # keeps syncing instead of dropping out of the loop entirely.
        users = (
            await db.scalars(
                select(User)
                .join(MailAccount, MailAccount.user_id == User.id)
                .where(
                    MailAccount.active.is_(True),
                    MailAccount.google_refresh_token.is_not(None),
                )
                .distinct()
            )
        ).all()
        for user in users:
            try:
                await sync_user(db, user)
            except Exception:
                # The rollback is the point. One user raising mid-transaction
                # used to leave the shared session in a failed state, so every
                # subsequent user died with PendingRollbackError — one bad
                # mailbox silently starved everyone after it, while the log line
                # below read as though the rest were fine.
                await db.rollback()
                logger.exception("sync failed for %s — continuing", user.email)


async def sync_loop() -> None:
    """In-process periodic sync. Sleeps first so short-lived processes
    (tests, --reload restarts) never fire a sync on startup."""
    interval = get_settings().sync_interval_minutes * 60
    while True:
        await asyncio.sleep(interval)
        try:
            await sync_all_users()
        except Exception:
            logger.exception("sync loop iteration failed")
