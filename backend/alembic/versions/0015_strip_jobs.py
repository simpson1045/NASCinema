"""strip_jobs — Track Manager Phase B (the actual strips)

Revision ID: 0015
Revises: 0014
Create Date: 2026-09-26
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "strip_jobs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("media_file_id", sa.Integer(), nullable=False),
        sa.Column("movie_id", sa.Integer(), nullable=True),
        sa.Column("path", sa.String(length=1024), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="queued"),
        sa.Column("phase", sa.String(length=16), nullable=True),
        sa.Column("progress", sa.Float(), nullable=False, server_default="0"),
        sa.Column("request", sa.String(length=16), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("savings_est", sa.BigInteger(), nullable=True),
        sa.Column("original_bytes", sa.BigInteger(), nullable=True),
        sa.Column("new_bytes", sa.BigInteger(), nullable=True),
        sa.Column("pre_strip_path", sa.String(length=1024), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_strip_jobs_status", "strip_jobs", ["status"])
    op.create_index("ix_strip_jobs_media_file_id", "strip_jobs", ["media_file_id"])


def downgrade() -> None:
    op.drop_table("strip_jobs")
