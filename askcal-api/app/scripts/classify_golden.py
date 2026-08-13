"""Run the real classifier over the golden set and report what it got wrong.

Prompt changes have been validated by waiting for real mail and seeing whether
it looked right, which finds a regression days later on the one message that
mattered. This asks the model the same twelve questions every time, so a prompt
edit is measurable in the minute you make it.

Costs a model call. Deliberately a script and not a test: the suite runs on
every change and must stay free of the network, a provider and an API budget.

    docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml \
        exec api uv run python -m app.scripts.classify_golden

    # locally, with a provider configured
    uv run python -m app.scripts.classify_golden
"""

import asyncio
import datetime as dt
import sys
from types import SimpleNamespace

from app.services.classifier import classifier_configured, classify_batch, parse_deadline
from app.services.tracks import BUILTIN_TRACKS
from tests.golden_set import GOLDEN


def _fake_track(spec: dict, index: int):
    """The built-in tracks as the prompt builder wants them.

    Plain objects rather than ORM rows: this needs the prompt the model sees,
    not a database, and running it should not require one.
    """
    return SimpleNamespace(
        slug=spec["slug"], description=spec["description"], sort_order=index
    )


def _as_email(case):
    """The corpus case in the shape the classifier reads."""
    return SimpleNamespace(
        gmail_id=case.id,
        sender=case.sender,
        subject=case.subject,
        body_text=case.body,
        snippet=case.body[:120],
        received_at=dt.datetime.now(dt.UTC),
        account=SimpleNamespace(
            label="golden",
            email="golden@example",
            tracks=[
                _fake_track(spec, i)
                for i, spec in enumerate(BUILTIN_TRACKS)
                if spec["slug"] in case.mailbox_tracks
            ],
        ),
    )


def _diff(case, got) -> list[str]:
    """Only what disagreed. A row of matching values is not a finding."""
    if got is None:
        return ["no answer"]

    wrong = []
    if case.assert_track and got.track != case.track:
        wrong.append(f"track {got.track} ≠ {case.track}")
    if got.action_required != case.action_required:
        wrong.append(f"action {got.action_required} ≠ {case.action_required}")
    # Consequence follows the track: an invoice read as money rather than as
    # client work is a different answer to the same question, not a second
    # mistake. Checked only where the filing itself is being asserted.
    if case.assert_track and got.consequence != case.consequence:
        wrong.append(f"consequence {got.consequence} ≠ {case.consequence}")
    if (parse_deadline(got.deadline_utc) is not None) != case.has_deadline:
        wrong.append("deadline " + ("invented" if got.deadline_utc else "missed"))
    return wrong


async def main() -> int:
    if not classifier_configured():
        print("No classifier configured — nothing to measure.")
        return 1

    emails = [_as_email(case) for case in GOLDEN]
    tracks = [_fake_track(spec, i) for i, spec in enumerate(BUILTIN_TRACKS)]
    answers = await classify_batch(emails, "Asia/Kolkata", tracks)

    failures = 0
    for case in GOLDEN:
        wrong = _diff(case, answers.get(case.id))
        if not wrong:
            print(f"  ok    {case.id}")
            continue
        failures += 1
        print(f"  WRONG {case.id}: {', '.join(wrong)}")
        # The rule the case exists to pin, printed only when it breaks — that
        # sentence is the argument for whatever the prompt should say instead.
        print(f"        {case.why}")

    print(f"\n{len(GOLDEN) - failures}/{len(GOLDEN)} correct.")
    # Non-zero on any disagreement, so this can gate a prompt change from a
    # shell without anyone reading the table.
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
