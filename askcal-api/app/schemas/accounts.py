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
    label: str | None  # what the user calls this mailbox
    # Track slugs this mailbox usually carries. Plural because no address is
    # one thing.
    tracks: list[str]
    last_synced_at: dt.datetime | None


class AccountsResponse(CamelModel):
    accounts: list[AccountOut]


class AccountLinkOut(CamelModel):
    url: str


class AccountPatchRequest(CamelModel):
    active: bool | None = None
    label: str | None = None
    # An empty list clears the leaning; omitting the field leaves it alone.
    # Collapsing those two would make "no usual track" and "do not touch it"
    # the same request.
    tracks: list[str] | None = None
