"""finance track value + routines table + tasks.scheduled_for

Revision ID: 0004
Revises: 0003
Create Date: 2026-07-07

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # New enum values can't be used inside the transaction that adds them —
    # commit the ALTER TYPE first, then backfill.
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE track_key ADD VALUE IF NOT EXISTS 'finance'")

    # every existing user gets an active finance track (new users get it
    # automatically via the per-TrackKey loop at login)
    op.execute(
        """
        INSERT INTO tracks (id, user_id, key, weight, active, created_at, updated_at)
        SELECT gen_random_uuid(), u.id, 'finance', 1.0, true, now(), now()
        FROM users u
        WHERE NOT EXISTS (
            SELECT 1 FROM tracks t WHERE t.user_id = u.id AND t.key = 'finance'
        )
        """
    )

    op.create_table(
        "routines",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("cadence", sa.String(40), nullable=False, server_default="daily"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_routines_user_id", "routines", ["user_id"])

    op.add_column("tasks", sa.Column("scheduled_for", sa.Date(), nullable=True))


def downgrade() -> None:
    op.drop_column("tasks", "scheduled_for")
    op.drop_index("ix_routines_user_id")
    op.drop_table("routines")
    op.execute("DELETE FROM tracks WHERE key = 'finance'")
    # PG can't remove an enum value; 'finance' stays in the type on downgrade
