"""movies.logo_url — manual clearlogo override

Revision ID: 0008
Revises: 0007
Create Date: 2026-06-30

TMDB tags every logo just by language (e.g. all "en"), so the US vs UK variant
(Sorcerer's vs Philosopher's Stone) can't be auto-picked — auto-selection goes
by vote and the original always wins. This lets an operator pin the right logo
per movie. Blank = fall back to the auto-picked TMDB logo.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("movies", sa.Column("logo_url", sa.String(length=1024), nullable=True))


def downgrade() -> None:
    op.drop_column("movies", "logo_url")
