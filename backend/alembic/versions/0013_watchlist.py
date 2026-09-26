"""watchlist table — My List

Revision ID: 0013
Revises: 0012
Create Date: 2026-09-26

Movies saved to watch later. user_id NULL = the household (per-user lists
later without a schema change).
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "watchlist",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("movie_id", sa.Integer(),
                  sa.ForeignKey("movies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("added_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("movie_id", "user_id", name="uq_watchlist_movie_user"),
    )
    op.create_index("ix_watchlist_movie_id", "watchlist", ["movie_id"])


def downgrade() -> None:
    op.drop_index("ix_watchlist_movie_id", table_name="watchlist")
    op.drop_table("watchlist")
