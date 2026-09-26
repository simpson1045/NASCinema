"""flags table — couch-side problem reports

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-25

One row per press of the controller's View button (or F8): screen, movie,
trailer/movie position, app version, plus a screenshot saved under
<data_dir>/flags/<id>.png.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "flags",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("screen", sa.String(length=64), nullable=True),
        sa.Column("kind", sa.String(length=16), nullable=True),
        sa.Column("movie_id", sa.Integer(), nullable=True),
        sa.Column("movie_title", sa.String(length=256), nullable=True),
        sa.Column("media_file_id", sa.Integer(), nullable=True),
        sa.Column("position_seconds", sa.Float(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("context", sa.JSON(), nullable=True),
        sa.Column("has_screenshot", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("resolved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("resolution_note", sa.Text(), nullable=True),
    )
    op.create_index("ix_flags_movie_id", "flags", ["movie_id"])
    op.create_index("ix_flags_resolved", "flags", ["resolved"])


def downgrade() -> None:
    op.drop_index("ix_flags_resolved", table_name="flags")
    op.drop_index("ix_flags_movie_id", table_name="flags")
    op.drop_table("flags")
