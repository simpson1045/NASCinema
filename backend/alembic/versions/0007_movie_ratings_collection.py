"""movies: popularity, vote_count, external ratings (IMDB/RT/Metacritic), collection

Revision ID: 0007
Revises: 0006
Create Date: 2026-06-29

Adds the data behind ranked home-screen rails ("Popular", "Top Rated") and
series grouping:
  - popularity / vote_count       — from the TMDB details we already fetch
  - imdb_id                       — TMDB gives it; the key for OMDb lookups
  - imdb_rating / rt_score /
    metacritic                    — from OMDb (populated only when a key is set)
  - collection_id / collection_name — TMDB belongs_to_collection (series grouping)

All nullable + additive, so this is a safe forward-only change.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("movies", sa.Column("popularity", sa.Float(), nullable=True))
    op.add_column("movies", sa.Column("vote_count", sa.Integer(), nullable=True))
    op.add_column("movies", sa.Column("imdb_id", sa.String(length=32), nullable=True))
    op.add_column("movies", sa.Column("imdb_rating", sa.Float(), nullable=True))
    op.add_column("movies", sa.Column("rt_score", sa.Integer(), nullable=True))
    op.add_column("movies", sa.Column("metacritic", sa.Integer(), nullable=True))
    op.add_column("movies", sa.Column("collection_id", sa.Integer(), nullable=True))
    op.add_column(
        "movies", sa.Column("collection_name", sa.String(length=512), nullable=True)
    )
    op.create_index("ix_movies_imdb_id", "movies", ["imdb_id"])
    op.create_index("ix_movies_collection_id", "movies", ["collection_id"])


def downgrade() -> None:
    op.drop_index("ix_movies_collection_id", table_name="movies")
    op.drop_index("ix_movies_imdb_id", table_name="movies")
    op.drop_column("movies", "collection_name")
    op.drop_column("movies", "collection_id")
    op.drop_column("movies", "metacritic")
    op.drop_column("movies", "rt_score")
    op.drop_column("movies", "imdb_rating")
    op.drop_column("movies", "imdb_id")
    op.drop_column("movies", "vote_count")
    op.drop_column("movies", "popularity")
