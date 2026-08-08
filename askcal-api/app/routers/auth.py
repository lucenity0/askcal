from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import jwt
from fastapi import APIRouter, Response
from fastapi.responses import RedirectResponse
from sqlalchemy import select, update

from app.config import get_settings
from app.core.errors import AskcalError
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
from app.services.gmail import GoogleProfile, authorization_url, exchange_google_code

router = APIRouter(prefix="/auth", tags=["auth"])

# New accounts start with career + uni + finance; design activates when
# freelance work is added, feed once the profile is set up.
DEFAULT_ACTIVE_TRACKS = {TrackKey.career, TrackKey.uni, TrackKey.finance}


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


async def _login(profile: GoogleProfile, db: DbSession) -> tuple[User, str, str]:
    """Upsert the user from a verified Google profile → (user, access, refresh)."""
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
    return user, create_access_token(user.id), raw_refresh


@router.post("/google", response_model=AuthResponse)
async def google_auth(body: GoogleAuthRequest, db: DbSession) -> AuthResponse:
    profile = await exchange_google_code(body.code)
    user, access, raw_refresh = await _login(profile, db)
    return AuthResponse(
        access_token=access,
        refresh_token=raw_refresh,
        user=UserOut.model_validate(user),
    )


# ─── Mobile flow: /auth/google/start → Google → /auth/google/callback → app ──
# ASWebAuthenticationSession can't intercept a plain web redirect, so the API
# brokers the exchange and hands tokens back via the app's custom scheme.
# Requires {api_base_url}/auth/google/callback in the Google console client.

def _callback_url() -> str:
    return f"{get_settings().api_base_url}/auth/google/callback"


def _check_scheme(scheme: str) -> None:
    """Only schemes this deployment owns may receive tokens.

    This used to be a syntax check (`^[a-zA-Z][a-zA-Z0-9+.-]*$`), which accepts
    essentially any scheme. Since the callback redirects a freshly minted access
    token AND a 30-day refresh token into f"{scheme}://oauth#...", a link to
    /auth/google/start?scheme=evil made the API itself hand a victim's
    credentials to any app that had registered evil://.

    An allowlist, not a pattern: the set of schemes Askcal ships is known and
    tiny, and a pattern can only ever describe what a scheme looks like, never
    whether we meant it.
    """
    if scheme not in get_settings().oauth_callback_schemes:
        raise AskcalError(422, "INVALID_SCHEME", "Unknown callback scheme")


@router.get("/google/start")
async def google_start(scheme: str = "askcal") -> RedirectResponse:
    _check_scheme(scheme)
    s = get_settings()
    state = jwt.encode(
        {
            "scheme": scheme,
            "type": "oauth_state",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=10),
        },
        s.jwt_secret,
        algorithm=s.jwt_algorithm,
    )
    return RedirectResponse(authorization_url(state, redirect_uri=_callback_url()))


@router.get("/google/callback")
async def google_callback(code: str, state: str, db: DbSession) -> RedirectResponse:
    s = get_settings()
    try:
        payload = jwt.decode(state, s.jwt_secret, algorithms=[s.jwt_algorithm])
        if payload.get("type") != "oauth_state":
            raise jwt.InvalidTokenError("wrong token type")
        scheme = payload["scheme"]
    except jwt.InvalidTokenError:
        raise AskcalError(401, "AUTH_EXPIRED", "OAuth state invalid or expired")

    # Re-checked on the way out, not just on the way in. The state is signed, so
    # this should be unreachable — but it is the single line standing between a
    # signing-key mistake and handing out refresh tokens, and it costs nothing.
    _check_scheme(scheme)

    profile = await exchange_google_code(code, redirect_uri=_callback_url())
    user, access, raw_refresh = await _login(profile, db)

    fragment = urlencode(
        {
            "accessToken": access,
            "refreshToken": raw_refresh,
            "email": user.email,
            "name": user.name or "",
        }
    )
    return RedirectResponse(f"{scheme}://oauth#{fragment}")


@router.post("/refresh", response_model=RefreshResponse)
async def refresh(body: RefreshRequest, db: DbSession) -> RefreshResponse:
    token = await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_refresh_token(body.refresh_token)
        )
    )
    now = datetime.now(timezone.utc)
    if token is None or token.revoked_at is not None or token.expires_at <= now:
        raise AskcalError(401, "AUTH_EXPIRED", "Refresh token invalid or expired")
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
