"""Move tasks the UTC bug filed on the wrong day.

`create_task` and `patch_task` derived a task's day from its pinned time **in
UTC**. At UTC+5:30 anything pinned after 18:30 local is already tomorrow in UTC
and anything before 05:30 is still yesterday, so the row was filed on a
different day from the one the app had drawn — which read as a duplicate and
was actually one task showing up in two places.

That is fixed going forward (`local_day` in app/services/scheduling.py). This
moves the rows already filed wrong.

The signature is a task whose `scheduled_for` disagrees with the local day of
its own `scheduled_at`. Those two are always written together by the app — the
composer files a task on the day of the time you picked — so a disagreement is
the bug rather than a choice. Rows with no pinned time are never touched: there
is nothing to check them against, and guessing would move work nobody asked to
move.

Dry run unless you pass --apply.

    docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml \
        exec api uv run python -m app.scripts.fix_task_days
    ... look at the list ...
        exec api uv run python -m app.scripts.fix_task_days --apply
"""

import asyncio
import sys

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.db import SessionLocal
from app.models import Task, User
from app.services.scheduling import local_day


async def main(apply: bool) -> int:
    moved = 0
    async with SessionLocal() as db:
        tasks = (
            await db.scalars(
                select(Task)
                .where(Task.scheduled_at.is_not(None))
                .options(selectinload(Task.user))
                .order_by(Task.scheduled_for)
            )
        ).all()

        for task in tasks:
            user: User | None = task.user
            if user is None:
                continue
            if task.scheduled_at is None:  # filtered in SQL; narrows for the checker
                continue
            correct = local_day(task.scheduled_at, user.timezone)
            if task.scheduled_for == correct:
                continue

            moved += 1
            print(
                f"  {task.scheduled_for} -> {correct}  "
                f"[{user.timezone}] {task.title[:60]}"
            )
            if apply:
                task.scheduled_for = correct

        if not moved:
            print("Nothing filed on the wrong day.")
            return 0

        if apply:
            await db.commit()
            print(f"\nMoved {moved} task(s).")
        else:
            print(
                f"\n{moved} task(s) would move. Nothing changed — "
                "re-run with --apply to do it."
            )
    return moved


if __name__ == "__main__":
    asyncio.run(main("--apply" in sys.argv))
