"""What a track is, now that the user owns the answer.

The five tracks used to be an enum: baked into the database, the classifier's
prompt, the auto-task rules and the client's model layer. They described a
guess at someone's life rather than anyone's actual life — a PR review is work,
but it was filed as `design`, because the model was asked to pick from five
categories and that was the closest one there.

A track is now a row. The user names it, describes it, and the description is
what steers the classifier. This module owns the starting set, the slug rules,
and the prompt text built from whatever the user ended up with.
"""

import re
import unicodedata

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Track

__all__ = [
    "BUILTIN_TRACKS",
    "default_tracks",
    "fallback_track",
    "find_track",
    "slugify",
    "track_by_slug",
    "track_rules_block",
    "user_tracks",
]

# The set every new account starts with, in display order. `active` mirrors the
# old DEFAULT_ACTIVE_TRACKS: design switches on when freelance work is added,
# feed once the profile is set up.
#
# These are a starting point and nothing more. Every field here is editable
# afterwards, which is the entire point of the change.
BUILTIN_TRACKS: list[dict] = [
    {
        "slug": "career",
        "label": "Career",
        "description": (
            "job applications, online assessments (OA), interviews, recruiters, "
            "placements"
        ),
        "active": True,
        "auto_tasks": True,
    },
    {
        "slug": "uni",
        "label": "Uni",
        "description": "coursework, exams, assignments, professor/university emails",
        "active": True,
        "auto_tasks": True,
    },
    {
        "slug": "design",
        "label": "Design",
        "description": (
            "freelance client work, briefs, deliverables, client communication"
        ),
        "active": False,
        "auto_tasks": True,
    },
    {
        "slug": "finance",
        "label": "Finance",
        "description": (
            "invoices, payments due, banking alerts, fees — money matters that are "
            "important only when urgent (a payment reminder yes, a paid receipt no)"
        ),
        "active": True,
        "auto_tasks": True,
    },
    {
        "slug": "feed",
        "label": "Feed",
        "description": "newsletters and content worth reading but carrying no obligation",
        "active": False,
        # Read-later by definition. The one built-in that never makes work.
        "auto_tasks": False,
    },
]


def default_tracks() -> list[Track]:
    """The rows a brand-new account gets."""
    return [
        Track(
            slug=spec["slug"],
            label=spec["label"],
            description=spec["description"],
            is_builtin=True,
            sort_order=index,
            auto_tasks=spec["auto_tasks"],
            active=spec["active"],
        )
        for index, spec in enumerate(BUILTIN_TRACKS)
    ]


def slugify(label: str) -> str:
    """A stable identifier from whatever the user typed.

    Accents are folded rather than stripped so "Café" becomes `cafe`, not an
    empty string — the alternative silently rejects perfectly ordinary names.
    """
    folded = unicodedata.normalize("NFKD", label)
    ascii_only = folded.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_only.lower()).strip("-")
    return slug[:40]


def track_by_slug(tracks: list[Track], slug: str | None) -> Track | None:
    """Find a track by slug, tolerating whatever case the model returned.

    An unrecognised slug is not an error and never invents a track — it means
    the mail belongs to none of them, exactly as `"none"` always has.
    """
    if not slug or slug == "none":
        return None
    wanted = slug.strip().lower()
    for track in tracks:
        if track.slug.lower() == wanted:
            return track
    return None


def fallback_track(tracks: list[Track], mailbox_tracks: list[Track] | None = None) -> Track | None:
    """Where actionable mail goes when the model named no track.

    "There is something you must do, and it belongs nowhere" is a contradiction,
    but the model returns it — and the result was silent: no track meant no
    task, so a bank security alert sat in the inbox looking triaged while never
    becoming work. Nothing on screen could have explained that.

    Filing it somewhere is the lesser wrong. The mailbox's own tracks go first,
    because "this arrived at my college address" is a real signal even when the
    content was ambiguous; failing that, the first track that can make work.
    Only tracks that are on and set to auto-task are eligible — landing work in
    a track the user switched off would recreate the same silence one step
    further down.
    """
    def usable(candidates: list[Track]) -> Track | None:
        for track in sorted(candidates, key=lambda t: (t.sort_order, t.slug)):
            if track.active and track.auto_tasks:
                return track
        return None

    return usable(list(mailbox_tracks or [])) or usable(tracks)


async def user_tracks(db: AsyncSession, user_id) -> list[Track]:
    """Every track on the account, in display order — inactive ones included."""
    rows = (
        await db.scalars(
            select(Track)
            .where(Track.user_id == user_id)
            .order_by(Track.sort_order, Track.slug)
        )
    ).all()
    return list(rows)


async def find_track(db: AsyncSession, user_id, slug: str) -> Track | None:
    return await db.scalar(
        select(Track).where(Track.user_id == user_id, Track.slug == slug.strip().lower())
    )


def track_rules_block(tracks: list[Track]) -> str:
    """The classifier's track list, written from the user's own tracks.

    This replaces five hardcoded lines of prose. A user who adds a "work" track
    described as "anything from my team or about a PR" gets that sentence in
    the prompt, which is the only thing that can actually move a PR review out
    of `design`.

    Inactive tracks are still listed. Active decides whether mail there makes
    work, not whether the mail exists — leaving them out would push their mail
    into a neighbouring track and mislabel it permanently.
    """
    lines = [
        f"- {track.slug}: {track.description}"
        if track.description
        else f"- {track.slug}"
        for track in sorted(tracks, key=lambda t: (t.sort_order, t.slug))
    ]
    lines.append("- none: everything else (spam, paid receipts, promotions, notifications)")
    return "\n".join(lines)
