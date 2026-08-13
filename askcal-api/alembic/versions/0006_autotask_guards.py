"""Auto-task guards: classification attempt counter + one task per source email

Revision ID: 0006
Revises: 0005
"""

import sqlalchemy as sa

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Stops a permanently-unclassifiable email from being retried every sync
    # interval forever. server_default so existing rows get 0 without a backfill.
    op.add_column(
        "emails",
        sa.Column(
            "classify_attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    # Dedupe BEFORE the unique index, or this migration cannot be applied to any
    # deployment that has been running. Duplicates were reachable by exactly the
    # paths this index exists to close — the background loop racing an on-demand
    # POST /api/inbox/sync, and the swipe path in routers/inbox.py, which never
    # checked for an existing task — so assuming a clean table would turn the
    # first prod deploy into a failed `alembic upgrade` with no way forward.
    #
    # Keep the oldest task per source email: it is the one the user has
    # potentially already seen, scheduled, or acted on. ctid breaks ties for rows
    # created in the same transaction, where created_at is identical.
    op.execute(
        """
        DELETE FROM tasks t
        USING tasks keep
        WHERE t.source_email_id IS NOT NULL
          AND t.source_email_id = keep.source_email_id
          AND (t.created_at, t.ctid) > (keep.created_at, keep.ctid)
        """
    )

    # One task per source email, enforced by the database rather than only by the
    # application check. That check runs before a multi-second LLM call and cannot
    # see a concurrent pass's uncommitted insert, so it can only ever be advisory.
    #
    # Partial: quick-add tasks have no source email, and Postgres would allow
    # unlimited NULLs anyway — being explicit keeps the intent readable and the
    # index smaller.
    op.create_index(
        "uq_tasks_source_email_id",
        "tasks",
        ["source_email_id"],
        unique=True,
        postgresql_where=sa.text("source_email_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_tasks_source_email_id", table_name="tasks")
    op.drop_column("emails", "classify_attempts")
