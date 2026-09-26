"""movies.certification — content rating (PG-13, R …)

Revision ID: 0012
Revises: 0011
Create Date: 2026-09-26

The movie's content rating in settings.rating_region, from TMDB's release
dates. "" = none published; NULL = not looked up yet (backfill-certifications
fills those).
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("movies", sa.Column("certification", sa.String(length=16), nullable=True))


def downgrade() -> None:
    op.drop_column("movies", "certification")
