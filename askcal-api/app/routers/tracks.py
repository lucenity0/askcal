from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.errors import AskcalError
from app.deps import CurrentUser, DbSession
from app.models import TaskStatus, Track
from app.schemas.tracks import (
    ProfileRequest,
    ProfileResponse,
    TrackCreateRequest,
    TrackItem,
    TrackOut,
    TrackPatchRequest,
    TracksResponse,
    TrackSettingOut,
)
from app.services.autotask import reconsider_auto_tasks
from app.services.brew_engine import SCORE_THRESHOLDS
from app.services.profile import STUDENT_TYPES, WORK_TYPES, profile_track_settings
from app.services.tracks import find_track, slugify

router = APIRouter(prefix="/api", tags=["tracks"])

# "urgent" = high-consequence by itself (top scoring band)
URGENT_THRESHOLD = SCORE_THRESHOLDS["long_black"]


async def _track_or_404(db, user, slug: str) -> Track:
    track = await find_track(db, user.id, slug)
    if track is None:
        raise AskcalError(404, "NOT_FOUND", f"No '{slug}' track on this account")
    return track


def _setting_out(track: Track) -> TrackSettingOut:
    return TrackSettingOut(id=track.slug, weight=track.weight, active=track.active)


@router.patch("/tracks/{slug}", response_model=TrackSettingOut)
async def update_track(
    slug: str, body: TrackPatchRequest, user: CurrentUser, db: DbSession
) -> TrackSettingOut:
    """Rename a track, rewrite what belongs in it, or turn it on and off.

    Exists because a track being inactive silently blocks auto-tasking for every
    mail filed under it, and until recently nothing in the app could turn one on.
    Design ships inactive by default — so design mail scored 97, sat in the
    inbox, and never became a task, with no way to find out why or change it.

    The description matters as much as the switch: it goes into the classifier
    prompt verbatim, so it is the only thing that can move mail out of a track
    it never belonged in.
    """
    track = await _track_or_404(db, user, slug)
    fields = body.model_fields_set

    if "label" in fields and body.label is not None:
        label = body.label.strip()
        if not label:
            raise AskcalError(422, "INVALID_TRACK", "A track needs a name")
        track.label = label
    if "description" in fields:
        track.description = (body.description or "").strip() or None
    if "active" in fields and body.active is not None:
        track.active = body.active
    if "auto_tasks" in fields and body.auto_tasks is not None:
        track.auto_tasks = body.auto_tasks
    if "weight" in fields and body.weight is not None:
        track.weight = body.weight

    await db.commit()

    # Any of these can change the answer to "should this mail have been a task",
    # so all of them re-run the gates. Mail is only put through them once, when
    # it is first classified — without this a track switched on today would do
    # nothing for everything already sitting in the inbox, which is exactly how
    # it behaved and gave no sign of it.
    if track.active and track.auto_tasks:
        await reconsider_auto_tasks(db, user)

    return _setting_out(track)


@router.post("/tracks", response_model=TrackOut, status_code=201)
async def create_track(
    body: TrackCreateRequest, user: CurrentUser, db: DbSession
) -> TrackOut:
    """Add a track of your own.

    The point of the whole change: a PR review is work, and no amount of prompt
    tuning files it correctly while the only categories on offer are someone
    else's five.
    """
    label = body.label.strip()
    if not label:
        raise AskcalError(422, "INVALID_TRACK", "A track needs a name")

    slug = slugify(label)
    if not slug:
        raise AskcalError(422, "INVALID_TRACK", f"Can't make a name out of '{label}'")
    if await find_track(db, user.id, slug) is not None:
        raise AskcalError(409, "DUPLICATE_TRACK", f"There's already a '{label}' track")

    last = await db.scalar(
        select(Track.sort_order)
        .where(Track.user_id == user.id)
        .order_by(Track.sort_order.desc())
        .limit(1)
    )
    track = Track(
        user_id=user.id,
        slug=slug,
        label=label,
        description=(body.description or "").strip() or None,
        is_builtin=False,
        sort_order=(last or 0) + 1,
        active=body.active,
        auto_tasks=body.auto_tasks,
    )
    db.add(track)
    await db.commit()
    await db.refresh(track)

    # A new track is retroactive too: mail already classified is re-examined
    # against it. Without this a track added today would only ever apply to
    # mail that arrives tomorrow.
    if track.active and track.auto_tasks:
        await reconsider_auto_tasks(db, user)

    return _track_out(track, [])


@router.delete("/tracks/{slug}", status_code=204)
async def delete_track(slug: str, user: CurrentUser, db: DbSession) -> None:
    """Remove a track the user added.

    Its tasks are left untracked rather than reassigned. A forced move would be
    a lie about where that work belonged, and deleting the work outright would
    lose things the user never asked to lose.

    Built-ins cannot be deleted — they can be renamed to anything and switched
    off, which covers every reason to want them gone without stranding the mail
    already filed under them.
    """
    track = await _track_or_404(db, user, slug)
    if track.is_builtin:
        raise AskcalError(
            422,
            "BUILTIN_TRACK",
            f"'{track.label}' can be renamed or turned off, but not deleted",
        )
    await db.delete(track)
    await db.commit()


def _track_out(track: Track, open_tasks: list) -> TrackOut:
    return TrackOut(
        id=track.slug,
        label=track.label,
        description=track.description,
        active=track.active,
        auto_tasks=track.auto_tasks,
        is_builtin=track.is_builtin,
        weight=track.weight,
        task_count=len(open_tasks),
        urgent_count=sum(1 for t in open_tasks if t.regret_score >= URGENT_THRESHOLD),
        items=[
            TrackItem(
                id=t.id,
                title=t.title,
                status=t.stage,
                pipeline=t.pipeline.value if t.pipeline else None,
                due_at=t.due_at,
            )
            for t in open_tasks
        ],
    )


@router.get("/tracks", response_model=TracksResponse)
async def get_tracks(user: CurrentUser, db: DbSession) -> TracksResponse:
    """Every track, active or not.

    Returning only the active ones meant the client could not show a switch in
    its real state without a second call — so a track that was off was simply
    absent, which is indistinguishable from not existing.
    """
    tracks = (
        await db.scalars(
            select(Track)
            .where(Track.user_id == user.id)
            .options(selectinload(Track.tasks))
            .order_by(Track.sort_order, Track.slug)
        )
    ).all()

    out = []
    for track in tracks:
        open_tasks = sorted(
            (t for t in track.tasks if t.status != TaskStatus.done),
            key=lambda t: (t.due_at is None, t.due_at),
        )
        out.append(_track_out(track, open_tasks))
    return TracksResponse(tracks=out)


@router.post("/profile", response_model=ProfileResponse)
async def set_profile(
    body: ProfileRequest, user: CurrentUser, db: DbSession
) -> ProfileResponse:
    """Onboarding answers → per-track weight + active flags."""
    if body.student_type not in STUDENT_TYPES:
        raise AskcalError(422, "INVALID_PROFILE", f"Unknown studentType '{body.student_type}'")
    if body.work_type not in WORK_TYPES:
        raise AskcalError(422, "INVALID_PROFILE", f"Unknown workType '{body.work_type}'")

    settings = profile_track_settings(body.student_type, body.work_type)
    tracks = (await db.scalars(select(Track).where(Track.user_id == user.id))).all()
    for track in tracks:
        # Onboarding only has an opinion about the five it shipped with. A track
        # the user made is theirs; re-answering a questionnaire must not quietly
        # switch it off.
        setting = settings.get(track.slug)
        if setting is None:
            continue
        track.weight, track.active = setting
    await db.commit()

    return ProfileResponse(
        tracks=[
            _setting_out(t) for t in sorted(tracks, key=lambda t: (t.sort_order, t.slug))
        ]
    )
