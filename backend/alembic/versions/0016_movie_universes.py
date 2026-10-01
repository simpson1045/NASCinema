"""movies.release_date + movies.universes — curated franchise tiles

Revision ID: 0016
Revises: 0015
Create Date: 2026-10-01

TMDB has collections (Iron Man, Toy Story) but nothing for the MCU, Disney
Animation or Pixar. `universes` holds which of those a movie belongs to
(["mcu"], ["pixar"] …, from TMDB keywords/companies); `release_date` sorts
them in true release order.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("movies", sa.Column("release_date", sa.String(10), nullable=True))
    op.add_column("movies", sa.Column("universes", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("movies", "universes")
    op.drop_column("movies", "release_date")
