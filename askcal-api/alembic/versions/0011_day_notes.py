"""A page you can write on

Revision ID: 0011
Revises: 0010

Askcal could only hold things with a shape — a task, a mail, a track. Anything
that was just a thought about the day had nowhere to go, which is a strange gap
in something built to look like a notebook.

One note per day, keyed on the day rather than on a note id: a dated page is
what the metaphor already promised, and it needs no browsing UI of its own.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "day_notes",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # The user's local day. Stored as a plain date, not a timestamp: a note
        # belongs to the page headed "August 12", and converting that through a
        # timezone would move it to a different page for the same person.
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        # One page per day. The write path is an upsert on this pair, so the
        # constraint is what makes concurrent saves from two devices land on the
        # same row instead of quietly making a second one.
        sa.UniqueConstraint("user_id", "day", name="uq_day_notes_user_day"),
    )
    op.create_index("ix_day_notes_user_day", "day_notes", ["user_id", "day"])


def downgrade() -> None:
    op.drop_index("ix_day_notes_user_day", table_name="day_notes")
    op.drop_table("day_notes")
