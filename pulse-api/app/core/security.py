"""JWT access tokens + opaque refresh tokens.

Access tokens are short-lived stateless JWTs. Refresh tokens are opaque
random strings stored SHA-256-hashed in the refresh_tokens table, so
POST /auth/revoke can actually revoke them.
"""

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt

from app.config import get_settings


def create_access_token(user_id: uuid.UUID) -> str:
    s = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=s.access_token_ttl_minutes),
        "type": "access",
    }
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm)


def decode_access_token(token: str) -> uuid.UUID:
    """Returns the user id. Raises jwt.InvalidTokenError on any problem."""
    s = get_settings()
    payload = jwt.decode(token, s.jwt_secret, algorithms=[s.jwt_algorithm])
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("not an access token")
    return uuid.UUID(payload["sub"])


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def new_refresh_token() -> tuple[str, str]:
    """Returns (raw_token_for_client, sha256_hash_for_db)."""
    raw = secrets.token_urlsafe(48)
    return raw, hash_refresh_token(raw)
