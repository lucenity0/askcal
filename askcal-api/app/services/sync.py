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
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.errors import AskcalError
from app.db import SessionLocal
from app.llm.base import LLMLimitError
from app.models import Email, Track, User
from app.services.autotask import (
    AUTO_TASK_TRACKS,
    NON_TASKING_CONSEQUENCES,
    build_task,
    open_task_exists_for_thread,
    should_auto_task,
)
from app.services.classifier import (
    classifier_configured,
    classify_batch,
    classify_pacing,
    signals_track_key,
)
from app.services.gmail import fetch_recent_messages
from app.services.regret import compute_regret
from app.services.scheduling import local_midnight, user_today

logger = logging.getLogger("askcal.sync")

# Re-exported: the gating rule lives in autotask.py (shared with the manual
# swipe path) but has always been imported from here.
__all__ = [
    "AUTO_TASK_TRACKS",
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


async def _store_new_messages(db: AsyncSession, user: User) -> SyncResult:
    result = SyncResult()
    messages = await fetch_recent_messages(
        user.google_refresh_token, since=local_midnight(user.timezone)
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
                    account_email=user.email,
                    subject=m.subject,
                    sender=m.sender,
                    snippet=m.snippet,
                    body_text=m.body_text,
                    received_at=m.received_at,
                    raw=m.raw,
                )
            )
            result.new += 1
    user.last_synced_at = datetime.now(timezone.utc)
    await db.commit()
    return result


async def _classify_pending(db: AsyncSession, user: User) -> tuple[int, int]:
    """→ (classified count, auto-created task count)."""
    # Guards the SELECT below, not just the LLM call: with no provider there is
    # no point querying pending mail every sync interval.
    if not classifier_configured():
        return 0, 0

    s = get_settings()
    pending = (
        await db.scalars(
            select(Email)
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
            # Claim the rows. These are held across a multi-second LLM call, and
            # the background loop and an on-demand POST /api/inbox/sync run in
            # the same process — the user pulls to refresh while the loop is
            # mid-batch. Without the lock both passes select the same email,
            # both call the model, and both create a task for it.
            .with_for_update(skip_locked=True)
        )
    ).all()
    if not pending:
        return 0, 0

    tracks_by_key = {
        t.key: t
        for t in (await db.scalars(select(Track).where(Track.user_id == user.id))).all()
    }

    classified = 0
    auto_tasked = 0
    now = datetime.now(timezone.utc)
    today = user_today(user.timezone)
    tasked_threads: set[str] = set()
    batch_size, delay = classify_pacing()
    for start in range(0, len(pending), batch_size):
        chunk = list(pending[start : start + batch_size])
        if start > 0 and delay:
            await asyncio.sleep(delay)
        try:
            signals_by_id = await classify_batch(chunk)
        except LLMLimitError:
            # Out of allowance, not broken. Grinding the remaining chunks against
            # the wall just burns retries against a limit that only time fixes.
            logger.warning("LLM quota reached — stopping this pass, resuming next sync")
            break
        except Exception:
            logger.exception("classification call failed; will retry next sync")
            _record_attempt(chunk)
            await db.commit()
            continue
        for email in chunk:
            signals = signals_by_id.get(email.gmail_id)
            if signals is None:
                # Omitted or mangled. Counted so a message the model can never
                # produce valid signals for eventually stops being retried.
                email.classify_attempts += 1
                continue
            track = signals_track_key(signals)
            track_row = tracks_by_key.get(track) if track else None
            email.track = track
            email.estimated_minutes = signals.estimated_minutes
            email.signals = signals.model_dump()
            email.regret_score = compute_regret(
                signals,
                track_weight=track_row.weight if track_row else 1.0,
                now=now,
            )
            email.classified_at = now
            classified += 1

            if not should_auto_task(signals, track, track_row, email.regret_score):
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
            db.add(build_task(email, signals.deadline_utc, track_row, today))
            if email.thread_id:
                tasked_threads.add(email.thread_id)
            email.handled = True
            auto_tasked += 1
        await db.commit()
    return classified, auto_tasked


def _record_attempt(chunk: list[Email]) -> None:
    for email in chunk:
        email.classify_attempts += 1


async def sync_user(db: AsyncSession, user: User) -> SyncResult:
    """Full pass for one user. Raises GMAIL_DISCONNECTED if auth is dead."""
    if not user.google_refresh_token:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "No Gmail connection for this account")
    result = await _store_new_messages(db, user)
    result.classified, result.auto_tasked = await _classify_pending(db, user)
    logger.info(
        "sync %s: fetched=%d new=%d classified=%d auto_tasked=%d",
        user.email, result.fetched, result.new, result.classified, result.auto_tasked,
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
        users = (
            await db.scalars(select(User).where(User.google_refresh_token.is_not(None)))
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
