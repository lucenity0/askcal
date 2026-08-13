"""Tracks the user owns.

The five tracks used to be an enum. A PR review is work, but it was filed as
`design`, because the model was asked to pick from five categories and that was
the closest one there. These pin the pieces that make a track a thing the user
names: the slug rules, resolving a model's answer against their tracks, and the
prompt built from their own descriptions.
"""

from types import SimpleNamespace

import pytest

from app.services.classifier import system_prompt
from app.services.profile import profile_track_settings
from app.services.tracks import (
    BUILTIN_TRACKS,
    default_tracks,
    slugify,
    track_by_slug,
    track_rules_block,
)


def track(slug: str, description: str | None = None, sort_order: int = 0):
    return SimpleNamespace(slug=slug, description=description, sort_order=sort_order)


# ── slugs ──────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "label, expected",
    [
        ("Work", "work"),
        ("Side projects", "side-projects"),
        ("  Uni  ", "uni"),
        ("PR / review", "pr-review"),
        ("Café", "cafe"),  # folded, not dropped — an empty slug rejects a real name
        ("!!!", ""),
    ],
)
def test_slugify(label, expected):
    assert slugify(label) == expected


def test_a_slug_stays_short_enough_for_the_column():
    assert len(slugify("a" * 200)) <= 40


# ── resolving what the model answered ──────────────────────────────────────


def test_a_known_slug_resolves():
    tracks = [track("work"), track("uni")]
    assert track_by_slug(tracks, "uni") is tracks[1]


def test_case_and_padding_do_not_lose_a_track():
    tracks = [track("work")]
    assert track_by_slug(tracks, " Work ") is tracks[0]


@pytest.mark.parametrize("answer", ["none", "", None, "invented-by-the-model"])
def test_an_unrecognised_answer_means_no_track(answer):
    """It never invents one. An unknown slug degrades exactly as "none" does —
    the alternative is a track nobody made appearing in someone's settings."""
    assert track_by_slug([track("work")], answer) is None


# ── the prompt ─────────────────────────────────────────────────────────────


def test_the_prompt_is_written_from_the_users_own_tracks():
    tracks = [
        track("work", "anything from my team or about a PR", 0),
        track("college", "coursework and anything from a professor", 1),
    ]
    block = track_rules_block(tracks)
    assert "- work: anything from my team or about a PR" in block
    assert "- college: coursework and anything from a professor" in block
    # The five hardcoded ones are gone, not merely supplemented.
    assert "design" not in block
    assert block.rstrip().endswith("- none: everything else (spam, paid receipts, promotions, notifications)")


def test_a_track_with_no_description_still_appears():
    assert "- work" in track_rules_block([track("work")])


def test_tracks_are_listed_in_display_order():
    block = track_rules_block([track("b", None, 2), track("a", None, 1)])
    assert block.index("- a") < block.index("- b")


def test_the_system_prompt_carries_the_users_tracks():
    prompt = system_prompt([track("work", "PRs and anything from my team")])
    assert "PRs and anything from my team" in prompt
    # Still the same rules and the same schema underneath.
    assert "action_required" in prompt


def test_the_system_prompt_falls_back_to_the_built_ins():
    """Callable with no user in hand — tests, and any path without one."""
    prompt = system_prompt()
    for spec in BUILTIN_TRACKS:
        assert f"- {spec['slug']}:" in prompt


def test_the_system_prompt_is_stable_for_the_same_tracks():
    """It must not change call to call, or prompt caching stops working."""
    tracks = [track("work", "PRs")]
    assert system_prompt(tracks) == system_prompt(tracks)


# ── what a new account starts with ─────────────────────────────────────────


def test_a_new_account_gets_the_built_ins_named_and_described():
    tracks = default_tracks()
    assert [t.slug for t in tracks] == [s["slug"] for s in BUILTIN_TRACKS]
    assert all(t.label and t.description for t in tracks)
    assert all(t.is_builtin for t in tracks)


def test_the_read_later_track_ships_unable_to_make_work():
    feed = next(t for t in default_tracks() if t.slug == "feed")
    assert feed.auto_tasks is False
    assert all(t.auto_tasks for t in default_tracks() if t.slug != "feed")


# ── onboarding ─────────────────────────────────────────────────────────────


def test_onboarding_only_has_an_opinion_about_the_built_ins():
    """Re-answering a questionnaire must not silently switch off a track the
    user made. Onboarding predates it and knows nothing about it."""
    settings = profile_track_settings("student", "design")
    assert set(settings) == {"career", "uni", "design", "feed", "finance"}
    assert "work" not in settings


# ── actionable mail the model filed nowhere ───────────────────────────────


def usable_track(slug, order=0, active=True, auto_tasks=True):
    return SimpleNamespace(
        slug=slug, sort_order=order, active=active, auto_tasks=auto_tasks
    )


def test_actionable_mail_with_no_track_lands_in_the_mailbox_it_arrived_at():
    """"There is something to do, and it belongs nowhere" is a contradiction the
    model returns anyway — and it used to mean no task at all, silently, with
    the mail still sitting in the inbox looking triaged."""
    from app.services.tracks import fallback_track

    uni = usable_track("uni", 1)
    all_tracks = [usable_track("career", 0), uni]
    assert fallback_track(all_tracks, [uni]) is uni


def test_it_falls_back_to_the_first_track_that_can_make_work():
    from app.services.tracks import fallback_track

    career = usable_track("career", 0)
    assert fallback_track([career, usable_track("uni", 1)], []) is career


def test_a_track_that_is_off_never_receives_the_fallback():
    """Landing work in a track the user switched off recreates the same silence
    one step further down."""
    from app.services.tracks import fallback_track

    off = usable_track("career", 0, active=False)
    read_only = usable_track("feed", 1, auto_tasks=False)
    on = usable_track("uni", 2)
    assert fallback_track([off, read_only, on]) is on


def test_nothing_usable_means_nothing_invented():
    from app.services.tracks import fallback_track

    assert fallback_track([usable_track("feed", 0, auto_tasks=False)]) is None
    assert fallback_track([]) is None


def test_the_mailbox_is_only_preferred_when_it_can_take_work():
    """A mailbox tagged read-later must not swallow an actionable mail."""
    from app.services.tracks import fallback_track

    read_only = usable_track("feed", 0, auto_tasks=False)
    on = usable_track("uni", 1)
    assert fallback_track([read_only, on], [read_only]) is on
