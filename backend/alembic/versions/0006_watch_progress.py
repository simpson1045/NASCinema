"""watch_progress — per-file resume position + subtitle

Revision ID: 0006
Revises: 0005
Create Date: 2026-06-28
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "watch_progress",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "media_file_id",
            sa.Integer(),
            sa.ForeignKey("media_files.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "position_seconds", sa.Float(), nullable=False, server_default="0"
        ),
        sa.Column("subtitle_id", sa.String(length=128), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_watch_progress_media_file_id",
        "watch_progress",
        ["media_file_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_watch_progress_media_file_id", table_name="watch_progress")
    op.drop_table("watch_progress")
