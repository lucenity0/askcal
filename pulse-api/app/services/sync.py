"""Sync orchestration: Gmail fetch → store raw → classify → regret score.

Runs two ways, per the phase-2 decision:
- background: sync_loop() started from the app lifespan, every
  PULSE_SYNC_INTERVAL_MINUTES
- on demand: POST /api/inbox/sync schedules run_sync_for_user() as a
  background task

Classification never blocks ingestion — new mail lands in the emails table
immediately; unclassified rows are picked up here (and retried) in batches.
"""

import asyncio
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.errors import PulseError
from app.db import SessionLocal
from app.models import Email, Track, User
from app.services.classifier import classify_batch, signals_track_key
from app.services.gmail import fetch_recent_messages
from app.services.regret import compute_regret

logger = logging.getLogger("pulse.sync")

CLASSIFY_PASS_LIMIT = 50  # max unclassified emails handled per sync pass


@dataclass
class SyncResult:
    fetched: int = 0
    new: int = 0
    classified: int = 0


async def _store_new_messages(db: AsyncSession, user: User) -> SyncResult:
    result = SyncResult()
    messages = await fetch_recent_messages(user.google_refresh_token)
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


async def _classify_pending(db: AsyncSession, user: User) -> int:
    s = get_settings()
    if not s.gemini_api_key:
        return 0

    pending = (
        await db.scalars(
            select(Email)
            .where(Email.user_id == user.id, Email.classified_at.is_(None))
            .order_by(Email.received_at.desc())
            .limit(CLASSIFY_PASS_LIMIT)
        )
    ).all()
    if not pending:
        return 0

    track_weights = {
        t.key: t.weight
        for t in (await db.scalars(select(Track).where(Track.user_id == user.id))).all()
    }

    classified = 0
    now = datetime.now(timezone.utc)
    for start in range(0, len(pending), s.classify_batch_size):
        chunk = list(pending[start : start + s.classify_batch_size])
        if start > 0:
            await asyncio.sleep(s.classify_delay_seconds)
        try:
            signals_by_id = await classify_batch(chunk)
        except Exception:
            logger.exception("Gemini classification call failed; will retry next sync")
            continue
        for email in chunk:
            signals = signals_by_id.get(email.gmail_id)
            if signals is None:
                continue
            track = signals_track_key(signals)
            email.track = track
            email.estimated_minutes = signals.estimated_minutes
            email.signals = signals.model_dump()
            email.regret_score = compute_regret(
                signals,
                track_weight=track_weights.get(track, 1.0) if track else 1.0,
                now=now,
            )
            email.classified_at = now
            classified += 1
        await db.commit()
    return classified


async def sync_user(db: AsyncSession, user: User) -> SyncResult:
    """Full pass for one user. Raises GMAIL_DISCONNECTED if auth is dead."""
    if not user.google_refresh_token:
        raise PulseError(401, "GMAIL_DISCONNECTED", "No Gmail connection for this account")
    result = await _store_new_messages(db, user)
    result.classified = await _classify_pending(db, user)
    logger.info(
        "sync %s: fetched=%d new=%d classified=%d",
        user.email, result.fetched, result.new, result.classified,
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
