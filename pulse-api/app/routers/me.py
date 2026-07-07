from zoneinfo import ZoneInfo

from fastapi import APIRouter
from pydantic import Field

from app.core.errors import PulseError
from app.deps import CurrentUser, DbSession
from app.schemas.auth import UserOut
from app.schemas.base import CamelModel

router = APIRouter(prefix="/api", tags=["me"])


class MePatchRequest(CamelModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    timezone: str | None = Field(default=None, max_length=64)


@router.get("/me", response_model=UserOut)
async def get_me(user: CurrentUser) -> UserOut:
    return UserOut(id=user.id, email=user.email, name=user.name, timezone=user.timezone)


@router.patch("/me", response_model=UserOut)
async def patch_me(body: MePatchRequest, user: CurrentUser, db: DbSession) -> UserOut:
    """Update the display name and/or timezone. The app sends the device
    timezone so day plans land in the user's real local time, not UTC.
    Returns the saved record so the client can confirm success."""
    fields = body.model_fields_set
    if "name" in fields and body.name is not None:
        user.name = body.name.strip()
    if "timezone" in fields and body.timezone:
        try:
            ZoneInfo(body.timezone)
            user.timezone = body.timezone
        except (KeyError, ValueError):
            raise PulseError(422, "INVALID_TIMEZONE", f"Unknown timezone '{body.timezone}'")
    await db.commit()
    return UserOut(id=user.id, email=user.email, name=user.name, timezone=user.timezone)
