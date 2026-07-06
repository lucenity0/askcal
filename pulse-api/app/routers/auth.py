from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Response
from sqlalchemy import select, update

from app.config import get_settings
from app.core.errors import PulseError
from app.core.security import create_access_token, hash_refresh_token, new_refresh_token
from app.deps import CurrentUser, DbSession
from app.models import RefreshToken, Track, TrackKey, User
from app.schemas.auth import (
    AuthResponse,
    GoogleAuthRequest,
    RefreshRequest,
    RefreshResponse,
    UserOut,
)
from app.services.gmail import exchange_google_code

router = APIRouter(prefix="/auth", tags=["auth"])

# New accounts start with career + uni; design activates when freelance work
# is added, feed once the profile is set up (spec: "The four tracks").
DEFAULT_ACTIVE_TRACKS = {TrackKey.career, TrackKey.uni}


async def _issue_refresh_token(db: DbSession, user: User) -> str:
    raw, token_hash = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=token_hash,
            expires_at=datetime.now(timezone.utc)
            + timedelta(days=get_settings().refresh_token_ttl_days),
        )
    )
    return raw


@router.post("/google", response_model=AuthResponse)
async def google_auth(body: GoogleAuthRequest, db: DbSession) -> AuthResponse:
    profile = await exchange_google_code(body.code)

    user = await db.scalar(select(User).where(User.google_sub == profile.sub))
    if user is None:
        user = await db.scalar(select(User).where(User.email == profile.email))
    if user is None:
        user = User(email=profile.email, name=profile.name, google_sub=profile.sub)
        user.tracks = [
            Track(key=key, active=key in DEFAULT_ACTIVE_TRACKS) for key in TrackKey
        ]
        db.add(user)
    else:
        user.google_sub = profile.sub
        user.name = user.name or profile.name
    if profile.refresh_token:
        user.google_refresh_token = profile.refresh_token

    await db.flush()
    raw_refresh = await _issue_refresh_token(db, user)
    await db.commit()

    return AuthResponse(
        access_token=create_access_token(user.id),
        refresh_token=raw_refresh,
        user=UserOut.model_validate(user),
    )


@router.post("/refresh", response_model=RefreshResponse)
async def refresh(body: RefreshRequest, db: DbSession) -> RefreshResponse:
    token = await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_refresh_token(body.refresh_token)
        )
    )
    now = datetime.now(timezone.utc)
    if token is None or token.revoked_at is not None or token.expires_at <= now:
        raise PulseError(401, "AUTH_EXPIRED", "Refresh token invalid or expired")
    return RefreshResponse(access_token=create_access_token(token.user_id))


@router.post("/revoke", status_code=204)
async def revoke(user: CurrentUser, db: DbSession) -> Response:
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(timezone.utc))
    )
    await db.commit()
    return Response(status_code=204)
