"""The day's page.

One note per day, addressed by the day itself rather than by an id. A dated
page is what the notebook metaphor already promised, and addressing it that way
means the client never has to create one before it can write — it just PUTs the
day it is looking at.
"""

import datetime as dt

from fastapi import APIRouter
from sqlalchemy import select

from app.deps import CurrentUser, DbSession
from app.models import DayNote
from app.schemas.base import CamelModel
from app.services.scheduling import user_today

router = APIRouter(prefix="/api", tags=["notes"])

# Long enough for a day's thinking, short enough that a runaway paste cannot
# put a megabyte of text on every sync.
MAX_BODY = 20_000


class NoteOut(CamelModel):
    day: dt.date
    body: str
    updated_at: dt.datetime | None


class NoteWrite(CamelModel):
    body: str


class NotesResponse(CamelModel):
    notes: list[NoteOut]


def _out(day: dt.date, note: DayNote | None) -> NoteOut:
    """An empty page is a real answer, not a 404.

    A day with nothing written on it exists exactly as much as one with a
    paragraph; making the client handle a missing note differently would put
    that distinction in every caller for no reason.
    """
    if note is None:
        return NoteOut(day=day, body="", updated_at=None)
    return NoteOut(day=note.day, body=note.body, updated_at=note.updated_at)


@router.get("/notes/{day}", response_model=NoteOut)
async def get_note(day: dt.date, user: CurrentUser, db: DbSession) -> NoteOut:
    note = await db.scalar(
        select(DayNote).where(DayNote.user_id == user.id, DayNote.day == day)
    )
    return _out(day, note)


@router.get("/notes", response_model=NotesResponse)
async def list_notes(
    user: CurrentUser,
    db: DbSession,
    start: dt.date | None = None,
    end: dt.date | None = None,
) -> NotesResponse:
    """Every non-empty note in a range.

    The week strip wants to mark which days have been written on, and asking
    day by day would be seven requests to draw one row — the same mistake the
    month grid made before it could ask for a range.
    """
    today = user_today(user.timezone)
    start = start or today - dt.timedelta(days=7)
    end = end or today + dt.timedelta(days=7)

    notes = (
        await db.scalars(
            select(DayNote)
            .where(
                DayNote.user_id == user.id,
                DayNote.day >= start,
                DayNote.day <= end,
                DayNote.body != "",
            )
            .order_by(DayNote.day)
        )
    ).all()
    return NotesResponse(notes=[_out(n.day, n) for n in notes])


@router.put("/notes/{day}", response_model=NoteOut)
async def put_note(
    day: dt.date, body: NoteWrite, user: CurrentUser, db: DbSession
) -> NoteOut:
    """Write the day's page.

    An upsert, so the client never has to know whether a note already exists —
    and cleared text deletes the row rather than leaving an empty one, which
    keeps "has anything been written here" a question the database can answer.
    """
    text = body.body[:MAX_BODY]
    note = await db.scalar(
        select(DayNote).where(DayNote.user_id == user.id, DayNote.day == day)
    )

    if not text.strip():
        if note is not None:
            await db.delete(note)
            await db.commit()
        return _out(day, None)

    if note is None:
        note = DayNote(user_id=user.id, day=day, body=text)
        db.add(note)
    else:
        note.body = text
    await db.commit()
    await db.refresh(note)
    return _out(day, note)
