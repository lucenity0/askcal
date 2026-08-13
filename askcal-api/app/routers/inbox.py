import datetime as dt
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from fastapi import APIRouter, BackgroundTasks
from sqlalchemy import and_, func, or_, select

from app.config import get_settings
from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import Email, Track
from app.schemas.inbox import (
    EmailOut,
    HandleRequest,
    InboxResponse,
    SnoozeRequest,
    SnoozeResponse,
    SyncAccepted,
)
from app.routers.tasks import _task_full_out
from app.services.triage import mail_need
from app.schemas.tasks import TaskFullOut
from app.services.autotask import build_task
from app.services.brew_engine import temp_for_score
from app.services.gmail import mark_as_read
from app.services.scheduling import local_midnight, user_today
from app.services.sync import run_sync_for_user
from app.services.accounts import has_connected_mailbox, token_for_email
from app.services.tracks import find_track

router = APIRouter(prefix="/api", tags=["inbox"])


@router.get("/inbox", response_model=InboxResponse)
async def get_inbox(user: CurrentUser, db: DbSession) -> InboxResponse:
    """Unhandled mail, within the window — anything auto-tasked by the pipeline
    or already swiped is out.

    Both branches are bounded by `inbox_window_days`. The returning-from-snooze
    branch used to have no such bound, so a mail snoozed once came back every
    day forever and the inbox filled with months of it.
    """
    now = datetime.now(timezone.utc)
    window_start = now - timedelta(days=get_settings().inbox_window_days)
    emails = (
        await db.scalars(
            select(Email)
            .where(
                Email.user_id == user.id,
                Email.handled.is_(False),
                Email.received_at >= window_start,
                or_(
                    # fresh: arrived today, not snoozed away
                    and_(
                        Email.received_at >= local_midnight(user.timezone),
                        Email.snoozed_until.is_(None),
                    ),
                    # returning: snooze expired
                    and_(Email.snoozed_until.is_not(None), Email.snoozed_until <= now),
                ),
            )
            .order_by(Email.regret_score.desc().nulls_last(), Email.received_at.desc())
        )
    ).all()

    total = await db.scalar(
        select(func.count()).select_from(Email).where(Email.user_id == user.id)
    )
    unhandled = await db.scalar(
        select(func.count())
        .select_from(Email)
        .where(Email.user_id == user.id, Email.handled.is_(False))
    )

    return InboxResponse(
        emails=[
            EmailOut(
                id=e.gmail_id,
                track=e.track_ref.slug if e.track_ref else None,
                subject=e.subject,
                sender=e.sender,
                received_at=e.received_at,
                regret_score=e.regret_score,
                estimated_minutes=e.estimated_minutes,
                temp_indicator=temp_for_score(e.regret_score),
                needs=mail_need(e.signals, now),
                snippet=e.snippet,
            )
            for e in emails
        ],
        total=total or 0,
        unhandled=unhandled or 0,
    )


@router.post("/inbox/sync", response_model=SyncAccepted, status_code=202)
async def trigger_sync(
    user: CurrentUser, background_tasks: BackgroundTasks
) -> SyncAccepted:
    if not has_connected_mailbox(user):
        raise AskcalError(401, "GMAIL_DISCONNECTED", "No Gmail connection for this account")
    background_tasks.add_task(run_sync_for_user, user.id)
    return SyncAccepted(status="syncing", message="pulling fresh beans")


async def _get_inbox_email(db: DbSession, user: CurrentUser, gmail_id: str) -> Email:
    email = await db.scalar(
        select(Email).where(Email.user_id == user.id, Email.gmail_id == gmail_id)
    )
    if email is None:
        raise AskcalError(404, "NOT_FOUND", "No such email in your inbox")
    return email


@router.post("/inbox/{gmail_id}/handle", response_model=TaskFullOut, status_code=201)
async def handle_email(
    gmail_id: str,
    body: HandleRequest,
    user: CurrentUser,
    db: DbSession,
    background_tasks: BackgroundTasks,
) -> TaskFullOut:
    """Swipe right: the email becomes a Task on its classified track."""
    email = await _get_inbox_email(db, user, gmail_id)
    if email.handled:
        raise AskcalError(409, "ALREADY_HANDLED", "That one's already been handled")

    if body.track:
        track = await find_track(db, user.id, body.track)
        if track is None:
            raise AskcalError(422, "INVALID_TRACK", f"No '{body.track}' track on this account")
    else:
        # What the classifier filed it under. `track_id` rather than the old
        # enum column, so mail in a track the user invented can still be filed.
        track = await db.get(Track, email.track_id) if email.track_id else None
        if track is None:
            raise AskcalError(
                422,
                "UNCLASSIFIED",
                "Email hasn't been classified yet — pass a track to file it under",
            )

    # Same constructor the sync pipeline uses. These were two copies that had
    # already drifted — this one read the JSONB dict, that one the typed model —
    # so deadline sanitising and deadline-driven scheduling only ever reached
    # half the tasks Askcal creates.
    signals = email.signals or {}
    task = build_task(
        email, signals.get("deadline_utc"), track,
        user_today(user.timezone), user.timezone
    )
    email.handled = True
    db.add(task)
    await db.commit()
    await db.refresh(task, ["track"])

    # The mailbox it actually arrived at. The primary account's token would
    # mark nothing read and say nothing about it — that id does not exist over
    # there.
    if token := token_for_email(user, email):
        background_tasks.add_task(mark_as_read, token, gmail_id)

    return _task_full_out(task)


@router.post("/inbox/{gmail_id}/snooze", response_model=SnoozeResponse)
async def snooze_email(
    gmail_id: str, body: SnoozeRequest, user: CurrentUser, db: DbSession
) -> SnoozeResponse:
    """Swipe left: hide from the inbox until tomorrow morning (or `until`)."""
    email = await _get_inbox_email(db, user, gmail_id)

    until = body.until
    if until is None:
        try:
            tz = ZoneInfo(user.timezone)
        except (KeyError, ValueError):
            tz = timezone.utc
        tomorrow = datetime.now(tz).date() + dt.timedelta(days=1)
        until = datetime.combine(tomorrow, dt.time(8, 0), tzinfo=tz)

    email.snoozed_until = until
    await db.commit()
    return SnoozeResponse(snoozed_until=until)
