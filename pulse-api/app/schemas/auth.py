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
