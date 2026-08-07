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

    # One open task per source email, enforced by the database rather than only
    # by the application check. The application check runs before a multi-second
    # LLM call and cannot see a concurrent pass's uncommitted insert, so without
    # this the background loop and an on-demand sync can still both create a task
    # for the same email.
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
