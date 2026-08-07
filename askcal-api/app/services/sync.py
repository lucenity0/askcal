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
from app.models import Email, Task, Track, TrackKey, User
from app.services.classifier import (
    classifier_configured,
    classify_batch,
    classify_pacing,
    parse_deadline,
    signals_track_key,
)
from app.services.gmail import fetch_recent_messages
from app.services.regret import compute_regret
from app.services.scheduling import local_midnight, user_today

logger = logging.getLogger("askcal.sync")

CLASSIFY_PASS_LIMIT = 50  # max unclassified emails handled per sync pass

# tracks whose actionable mail turns into tasks automatically; feed is
# read-later by definition and never auto-tasks
AUTO_TASK_TRACKS = {TrackKey.career, TrackKey.design, TrackKey.uni, TrackKey.finance}

# A real task always has real stakes: social notifications ("add X", "someone
# viewed you") and zero-consequence FYIs are never work, even when the model
# marks them action_required — so gate on consequence.
#
# sender_type is deliberately NOT a gate. Legitimate tasks — assignment due,
# online assessment, bill payable — arrive from no-reply/automated systems
# exactly like noise does; filtering automated_system out silently drops real
# work (the original assignment-not-tasking bug). The prompt's action_required
# judgment is what separates a genuine ask from a notification.
NON_TASKING_CONSEQUENCES = {"social", "none"}


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


def should_auto_task(signals, track: TrackKey | None, track_row: Track | None) -> bool:
    """A mail auto-tasks when the model says the user must personally do a
    concrete task (action_required) with a real consequence, in a real
    (non-feed) work track that's active for this user. Channel/sender is not a
    gate — an assignment from a no-reply LMS is as real as a client email."""
    return bool(
        signals.action_required
        and signals.consequence not in NON_TASKING_CONSEQUENCES
        and track in AUTO_TASK_TRACKS
        and track_row is not None
        and track_row.active
    )


def _auto_task(email: Email, signals, track_row: Track, today) -> Task:
    """The daily-pipeline payoff: an actionable classified email becomes a
    task for today, no swipe needed."""
    return Task(
        user_id=email.user_id,
        track_id=track_row.id,
        source_email_id=email.id,
        title=email.subject or (email.snippet or "untitled")[:200],
        regret_score=email.regret_score or 0,
        estimated_hours=(
            round(email.estimated_minutes / 60, 1) if email.estimated_minutes else None
        ),
        due_at=parse_deadline(signals.deadline_utc),
        scheduled_for=today,
    )


async def _classify_pending(db: AsyncSession, user: User) -> tuple[int, int]:
    """→ (classified count, auto-created task count)."""
    # Guards the SELECT below, not just the LLM call: with no provider there is
    # no point querying pending mail every sync interval.
    if not classifier_configured():
        return 0, 0

    pending = (
        await db.scalars(
            select(Email)
            .where(Email.user_id == user.id, Email.classified_at.is_(None))
            .order_by(Email.received_at.desc())
            .limit(CLASSIFY_PASS_LIMIT)
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
            continue
        for email in chunk:
            signals = signals_by_id.get(email.gmail_id)
            if signals is None:
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

            if should_auto_task(signals, track, track_row):
                db.add(_auto_task(email, signals, track_row, today))
                email.handled = True
                auto_tasked += 1
        await db.commit()
    return classified, auto_tasked


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
