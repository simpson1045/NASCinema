"""media_files.fingerprint — Chromaprint audio fingerprint (Extras DB groundwork)

Revision ID: 0005
Revises: 0004
Create Date: 2026-06-24
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("media_files", sa.Column("fingerprint", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("media_files", "fingerprint")
