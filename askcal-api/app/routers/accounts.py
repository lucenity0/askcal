"""Connected mailboxes.

One Google account was baked into the user row, so college mail and personal
mail could not both reach Askcal. They want completely different treatment,
which is why user-defined tracks had to land first — "college mail is college
work, personal mail usually isn't" is a statement about tracks, not about
mailboxes.
"""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import APIRouter
from sqlalchemy import select

from app.config import get_settings
from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import MailAccount
from app.schemas.accounts import (
    AccountLinkOut,
    AccountOut,
    AccountPatchRequest,
    AccountsResponse,
)
from app.services.gmail import authorization_url
from app.services.tracks import find_track

router = APIRouter(prefix="/api", tags=["accounts"])

LINK_STATE_TYPE = "oauth_link"
LINK_STATE_TTL_MINUTES = 10


def _account_out(account: MailAccount) -> AccountOut:
    return AccountOut(
        id=account.id,
        email=account.email,
        is_primary=account.is_primary,
        active=account.active,
        connected=account.google_refresh_token is not None,
        label=account.label,
        tracks=[t.slug for t in sorted(account.tracks, key=lambda t: (t.sort_order, t.slug))],
        last_synced_at=account.last_synced_at,
    )


async def _accounts(db, user) -> list[MailAccount]:
    rows = (
        await db.scalars(
            select(MailAccount)
            .where(MailAccount.user_id == user.id)
            .order_by(MailAccount.is_primary.desc(), MailAccount.created_at)
        )
    ).all()
    return list(rows)


@router.get("/accounts", response_model=AccountsResponse)
async def list_accounts(user: CurrentUser, db: DbSession) -> AccountsResponse:
    return AccountsResponse(accounts=[_account_out(a) for a in await _accounts(db, user)])


@router.post("/accounts/link", response_model=AccountLinkOut)
async def start_link(user: CurrentUser, db: DbSession, scheme: str = "askcal") -> AccountLinkOut:
    """Begin connecting another mailbox.

    Authenticated, and returns a URL rather than redirecting, so the caller's
    access token never travels in a browser redirect. Who the new mailbox
    attaches to rides in the signed state instead — the browser carries a token
    we minted and can verify, not one that grants anything on its own.
    """
    s = get_settings()
    if scheme not in s.oauth_callback_schemes:
        raise AskcalError(422, "INVALID_SCHEME", "Unknown callback scheme")

    state = jwt.encode(
        {
            "type": LINK_STATE_TYPE,
            "scheme": scheme,
            "user_id": str(user.id),
            "exp": datetime.now(UTC) + timedelta(minutes=LINK_STATE_TTL_MINUTES),
        },
        s.jwt_secret,
        algorithm=s.jwt_algorithm,
    )
    return AccountLinkOut(
        url=authorization_url(state, redirect_uri=f"{s.api_base_url}/auth/google/callback")
    )


@router.patch("/accounts/{account_id}", response_model=AccountOut)
async def update_account(
    account_id: uuid.UUID, body: AccountPatchRequest, user: CurrentUser, db: DbSession
) -> AccountOut:
    """Name a mailbox, pause it, or say what its mail is usually about.

    Tracks are a leaning passed to the classifier, never a rule. An account that
    forced them would file a bill arriving at a college address as coursework
    every time, with nothing on screen explaining why.
    """
    account = await db.scalar(
        select(MailAccount).where(
            MailAccount.user_id == user.id, MailAccount.id == account_id
        )
    )
    if account is None:
        raise AskcalError(404, "NOT_FOUND", "No such account")

    fields = body.model_fields_set
    if "active" in fields and body.active is not None:
        account.active = body.active
    if "label" in fields:
        account.label = (body.label or "").strip() or None
    if "tracks" in fields and body.tracks is not None:
        resolved = []
        for slug in body.tracks:
            track = await find_track(db, user.id, slug)
            if track is None:
                raise AskcalError(
                    422, "INVALID_TRACK", f"No '{slug}' track on this account"
                )
            resolved.append(track)
        account.tracks = resolved
    await db.commit()
    await db.refresh(account)
    return _account_out(account)


@router.delete("/accounts/{account_id}", status_code=204)
async def unlink_account(account_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    """Disconnect a mailbox and forget its mail.

    Its tasks survive — `tasks.source_email_id` is ON DELETE SET NULL — because
    work you already agreed to do does not stop existing when you unlink the
    inbox it arrived at. Its unread mail does go, since mail you can no longer
    open is not something you can act on.

    The primary account cannot be unlinked: it owns the sign-in and the
    calendar. Pausing it is the way to stop it syncing.
    """
    account = await db.scalar(
        select(MailAccount).where(
            MailAccount.user_id == user.id, MailAccount.id == account_id
        )
    )
    if account is None:
        raise AskcalError(404, "NOT_FOUND", "No such account")
    if account.is_primary:
        raise AskcalError(
            422,
            "PRIMARY_ACCOUNT",
            "That's the account you sign in with — pause it instead of unlinking",
        )
    await db.delete(account)
    await db.commit()
