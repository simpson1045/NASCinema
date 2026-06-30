"""movies.trailer_youtube — manual trailer override

Revision ID: 0009
Revises: 0008
Create Date: 2026-06-30

A YouTube URL or key to use instead of TMDB's auto-picked trailer, for cases
where TMDB's best pick is a poor upload (e.g. a low-bitrate 2001 trailer). Blank
= fall back to the auto-selected trailer.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "movies", sa.Column("trailer_youtube", sa.String(length=256), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("movies", "trailer_youtube")
