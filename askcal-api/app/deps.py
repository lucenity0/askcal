from typing import Annotated

import jwt
from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AskcalError
from app.core.security import decode_access_token
from app.db import get_db
from app.models import User


async def get_current_user(
    db: Annotated[AsyncSession, Depends(get_db)],
    authorization: Annotated[str | None, Header()] = None,
) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AskcalError(401, "AUTH_EXPIRED", "Missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        user_id = decode_access_token(token)
    except (jwt.InvalidTokenError, ValueError):
        raise AskcalError(401, "AUTH_EXPIRED", "Invalid or expired access token")
    user = await db.get(User, user_id)
    if user is None:
        raise AskcalError(401, "AUTH_EXPIRED", "User no longer exists")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
DbSession = Annotated[AsyncSession, Depends(get_db)]
