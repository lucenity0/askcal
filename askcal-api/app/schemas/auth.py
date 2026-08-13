import uuid

from app.schemas.base import CamelModel


class GoogleAuthRequest(CamelModel):
    code: str


class UserOut(CamelModel):
    id: uuid.UUID
    email: str
    name: str | None
    timezone: str


class AuthResponse(CamelModel):
    access_token: str
    refresh_token: str
    user: UserOut


class RefreshRequest(CamelModel):
    refresh_token: str


class RefreshResponse(CamelModel):
    access_token: str
    # Rotation: the presented token is retired by this call, so the caller must
    # store this one. Returning it is not optional — a client that ignores it
    # has no way back once its own copy stops working.
    refresh_token: str
