"""Tracks the user can name themselves

Revision ID: 0008
Revises: 0007

Both shapes are present when this lands. `tracks.key` and `emails.track` keep
their values and stay readable; the new `slug`/`track_id` columns are filled
alongside them. Nothing reads the new columns yet, so this deploys on its own
and changes nothing anyone can see.

The old columns are dropped in a later migration, once no deployed code reads
them. A rollback that cannot recover its own data is not a rollback.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

# What the five built-ins are called once a name is something the user owns,
# and what each one means. Only the starting point — every one of these is
# renameable and rewritable afterwards.
#
# The descriptions are the track prose lifted out of the classifier's system
# prompt. They are copied in rather than imported: existing accounts must keep
# classifying exactly as they did, and a migration that changes meaning when
# app code changes later is not a migration.
BUILTINS = {
    "career": (
        "Career",
        "job applications, online assessments (OA), interviews, recruiters, "
        "placements",
    ),
    "design": (
        "Design",
        "freelance client work, briefs, deliverables, client communication",
    ),
    "uni": (
        "Uni",
        "coursework, exams, assignments, professor/university emails",
    ),
    "feed": (
        "Feed",
        "newsletters and content worth reading but carrying no obligation",
    ),
    "finance": (
        "Finance",
        "invoices, payments due, banking alerts, fees — money matters that are "
        "important only when urgent (a payment reminder yes, a paid receipt no)",
    ),
}

# Display order for the built-ins, so a fresh list is not in enum-definition
# order by accident.
ORDER = ["career", "uni", "design", "finance", "feed"]


def upgrade() -> None:
    op.add_column("tracks", sa.Column("slug", sa.String(40), nullable=True))
    op.add_column("tracks", sa.Column("label", sa.String(80), nullable=True))
    # Fed to the classifier prompt. This is the field that actually steers where
    # mail lands — a track named "work" tells the model very little on its own.
    op.add_column("tracks", sa.Column("description", sa.Text(), nullable=True))
    op.add_column(
        "tracks",
        sa.Column(
            "is_builtin", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
    )
    op.add_column(
        "tracks",
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    # Replaces the hardcoded AUTO_TASK_TRACKS set. With tracks the user invents
    # there is no fixed list to hardcode, and "does this track create work for
    # me" is a per-track question anyway.
    op.add_column(
        "tracks",
        sa.Column(
            "auto_tasks", sa.Boolean(), nullable=False, server_default=sa.true()
        ),
    )

    # Backfill from the enum. ::text because the comparison is against a
    # Postgres enum type, not a varchar.
    for key, (label, description) in BUILTINS.items():
        op.execute(
            sa.text(
                "UPDATE tracks SET slug = :slug, label = :label, "
                "description = :description, is_builtin = true, "
                "sort_order = :order WHERE key::text = :slug"
            ).bindparams(
                slug=key,
                label=label,
                description=description,
                order=ORDER.index(key),
            )
        )

    # feed is the one built-in that never auto-tasks — newsletters and digests
    # are things to read, not things to do.
    op.execute("UPDATE tracks SET auto_tasks = false WHERE key::text = 'feed'")

    # Anything the backfill missed would be a row with a key outside the enum,
    # which cannot exist. Safe to tighten now.
    op.alter_column("tracks", "slug", nullable=False)
    op.alter_column("tracks", "label", nullable=False)
    op.create_unique_constraint("uq_tracks_user_slug", "tracks", ["user_id", "slug"])

    # A user-defined track has no enum key to hold. Postgres permits repeated
    # NULLs in a unique constraint, so the existing (user_id, key) constraint
    # stays correct for the built-ins.
    op.alter_column("tracks", "key", nullable=True)

    op.add_column(
        "emails",
        sa.Column(
            "track_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tracks.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("ix_emails_track_id", "emails", ["track_id"])

    # Join on (user_id, key): a track row belongs to one user, and an email's
    # track only ever meant that user's track of that name.
    op.execute(
        """
        UPDATE emails e
           SET track_id = t.id
          FROM tracks t
         WHERE t.user_id = e.user_id
           AND t.key::text = e.track::text
           AND e.track IS NOT NULL
        """
    )


def downgrade() -> None:
    op.drop_index("ix_emails_track_id", table_name="emails")
    op.drop_column("emails", "track_id")

    # Rows added after the upgrade may have no key. They cannot be represented
    # in the old shape at all, so they go rather than silently becoming some
    # other track.
    op.execute("DELETE FROM tracks WHERE key IS NULL")
    op.alter_column("tracks", "key", nullable=False)

    op.drop_constraint("uq_tracks_user_slug", "tracks", type_="unique")
    for column in ("auto_tasks", "sort_order", "is_builtin", "description", "label", "slug"):
        op.drop_column("tracks", column)
