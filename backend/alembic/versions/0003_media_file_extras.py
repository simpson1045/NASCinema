"""media_files: kind / extra_type / extra_title (bonus features)

Revision ID: 0003
Revises: 0002
Create Date: 2026-06-24
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "media_files",
        sa.Column("kind", sa.String(length=16), nullable=False, server_default="feature"),
    )
    op.add_column(
        "media_files", sa.Column("extra_type", sa.String(length=32), nullable=True)
    )
    op.add_column(
        "media_files", sa.Column("extra_title", sa.String(length=512), nullable=True)
    )
    op.create_index("ix_media_files_kind", "media_files", ["kind"])


def downgrade() -> None:
    op.drop_index("ix_media_files_kind", table_name="media_files")
    op.drop_column("media_files", "extra_title")
    op.drop_column("media_files", "extra_type")
    op.drop_column("media_files", "kind")
