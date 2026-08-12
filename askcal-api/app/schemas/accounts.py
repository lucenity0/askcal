import datetime as dt
import uuid

from app.schemas.base import CamelModel


class AccountOut(CamelModel):
    id: uuid.UUID
    email: str
    is_primary: bool
    active: bool
    # Whether there is still a usable token. An account can exist without one
    # after Google revokes access, and "connected" is the only honest way to
    # show that rather than silently never syncing.
    connected: bool
    default_track: str | None  # track slug this mailbox's mail usually is
    last_synced_at: dt.datetime | None


class AccountsResponse(CamelModel):
    accounts: list[AccountOut]


class AccountLinkOut(CamelModel):
    url: str


class AccountPatchRequest(CamelModel):
    active: bool | None = None
    # Explicitly nullable: sending null clears the leaning, which is different
    # from omitting the field and leaving it alone.
    default_track: str | None = None
