"""initial schema — users, tracks, emails, tasks, refresh_tokens, day_logs

Revision ID: 0001
Revises:
Create Date: 2026-07-04

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

track_key = postgresql.ENUM("career", "design", "uni", "feed", name="track_key", create_type=False)
task_status = postgresql.ENUM("pending", "done", "carried", name="task_status", create_type=False)
career_pipeline = postgresql.ENUM(
    "applied", "oa", "interview", "offer", "reject", name="career_pipeline", create_type=False
)


def upgrade() -> None:
    bind = op.get_bind()
    for enum in (track_key, task_status, career_pipeline):
        enum.create(bind, checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False, unique=True),
        sa.Column("name", sa.String(200), nullable=True),
        sa.Column("google_sub", sa.String(64), nullable=True, unique=True),
        sa.Column("google_refresh_token", sa.Text(), nullable=True),
        sa.Column("timezone", sa.String(64), nullable=False),
        sa.Column("carry_forward_sensitivity", sa.Float(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
    )

    op.create_table(
        "tracks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("key", track_key, nullable=False),
        sa.Column("weight", sa.Float(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.UniqueConstraint("user_id", "key"),
    )
    op.create_index("ix_tracks_user_id", "tracks", ["user_id"])

    op.create_table(
        "emails",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("gmail_id", sa.String(64), nullable=False),
        sa.Column("thread_id", sa.String(64), nullable=True),
        sa.Column("account_email", sa.String(320), nullable=True),
        sa.Column("subject", sa.Text(), nullable=True),
        sa.Column("sender", sa.String(320), nullable=True),
        sa.Column("snippet", sa.Text(), nullable=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("raw", postgresql.JSONB(), nullable=True),
        sa.Column("track", track_key, nullable=True),
        sa.Column("regret_score", sa.Integer(), nullable=True),
        sa.Column("estimated_minutes", sa.Integer(), nullable=True),
        sa.Column("classified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("handled", sa.Boolean(), nullable=False),
        sa.Column("snoozed_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.UniqueConstraint("user_id", "gmail_id"),
    )
    op.create_index("ix_emails_user_id", "emails", ["user_id"])
    op.create_index("ix_emails_thread_id", "emails", ["thread_id"])
    op.create_index("ix_emails_received_at", "emails", ["received_at"])

    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "track_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tracks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "source_email_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("emails.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("stage", sa.String(50), nullable=True),
        sa.Column("pipeline", career_pipeline, nullable=True),
        sa.Column("regret_score", sa.Integer(), nullable=False),
        sa.Column("estimated_hours", sa.Float(), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", task_status, nullable=False),
        sa.Column("carried_count", sa.Integer(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
    )
    op.create_index("ix_tasks_user_id", "tasks", ["user_id"])
    op.create_index("ix_tasks_track_id", "tasks", ["track_id"])

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])

    op.create_table(
        "day_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("pulled_count", sa.Integer(), nullable=False),
        sa.Column("remaining_count", sa.Integer(), nullable=False),
        sa.Column("projected_brew", sa.String(20), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.UniqueConstraint("user_id", "date"),
    )
    op.create_index("ix_day_logs_user_id", "day_logs", ["user_id"])


def downgrade() -> None:
    op.drop_table("day_logs")
    op.drop_table("refresh_tokens")
    op.drop_table("tasks")
    op.drop_table("emails")
    op.drop_table("tracks")
    op.drop_table("users")
    bind = op.get_bind()
    for enum in (career_pipeline, task_status, track_key):
        enum.drop(bind, checkfirst=True)
