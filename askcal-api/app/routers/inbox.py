import datetime as dt
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import APIRouter, BackgroundTasks
from sqlalchemy import and_, func, or_, select

from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import Email, Task, Track, TrackKey
from app.schemas.inbox import (
    EmailOut,
    HandleRequest,
    InboxResponse,
    SnoozeRequest,
    SnoozeResponse,
    SyncAccepted,
)
from app.routers.tasks import _task_full_out
from app.schemas.tasks import TaskFullOut
from app.services.brew_engine import temp_for_score
from app.services.classifier import parse_deadline
from app.services.gmail import mark_as_read
from app.services.scheduling import local_midnight, user_today
from app.services.sync import run_sync_for_user

router = APIRouter(prefix="/api", tags=["inbox"])


@router.get("/inbox", response_model=InboxResponse)
async def get_inbox(user: CurrentUser, db: DbSession) -> InboxResponse:
    """Today's unhandled mail only — anything auto-tasked by the pipeline or
    already swiped is out; yesterday's leftovers don't resurface."""
    now = datetime.now(timezone.utc)
    emails = (
        await db.scalars(
            select(Email)
            .where(
                Email.user_id == user.id,
                Email.handled.is_(False),
                or_(
                    # fresh: arrived today, not snoozed away
                    and_(
                        Email.received_at >= local_midnight(user.timezone),
                        Email.snoozed_until.is_(None),
                    ),
                    # returning: snooze expired (regardless of arrival day)
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
                track=e.track.value if e.track else None,
                subject=e.subject,
                sender=e.sender,
                received_at=e.received_at,
                regret_score=e.regret_score,
                estimated_minutes=e.estimated_minutes,
                temp_indicator=temp_for_score(e.regret_score),
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
    if not user.google_refresh_token:
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
        try:
            track_key = TrackKey(body.track)
        except ValueError:
            raise AskcalError(422, "INVALID_TRACK", f"Unknown track '{body.track}'")
    else:
        track_key = email.track
    if track_key is None:
        raise AskcalError(
            422, "UNCLASSIFIED", "Email hasn't been classified yet — pass a track to file it under"
        )
    track = await db.scalar(
        select(Track).where(Track.user_id == user.id, Track.key == track_key)
    )
    if track is None:
        raise AskcalError(422, "INVALID_TRACK", f"No '{track_key.value}' track on this account")

    signals = email.signals or {}
    task = Task(
        user_id=user.id,
        track_id=track.id,
        source_email_id=email.id,
        title=email.subject or (email.snippet or "untitled")[:200],
        regret_score=email.regret_score or 0,
        estimated_hours=(
            round(email.estimated_minutes / 60, 1) if email.estimated_minutes else None
        ),
        due_at=parse_deadline(signals.get("deadline_utc")),
        scheduled_for=user_today(user.timezone),
    )
    email.handled = True
    db.add(task)
    await db.commit()
    await db.refresh(task, ["track"])

    if user.google_refresh_token:
        background_tasks.add_task(mark_as_read, user.google_refresh_token, gmail_id)

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
