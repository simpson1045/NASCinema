"""TV shows — shows, seasons, episodes; media_files.episode_id

Revision ID: 0017
Revises: 0016
Create Date: 2026-10-11

An episode's files are ordinary media_files rows (kind='episode'), so
streaming, resume points and subtitles need nothing new. New tables only,
plus one nullable column — existing movie data is untouched.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "shows",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("folder", sa.String(1024), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("year", sa.Integer()),
        sa.Column("tmdb_id", sa.Integer()),
        sa.Column("overview", sa.Text()),
        sa.Column("poster_path", sa.String(512)),
        sa.Column("backdrop_path", sa.String(512)),
        sa.Column("genres", sa.JSON()),
        sa.Column("rating", sa.Float()),
        sa.Column("certification", sa.String(16)),
        sa.Column("status", sa.String(32)),
        sa.Column("first_air_date", sa.String(10)),
        sa.Column("added_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_shows_folder", "shows", ["folder"], unique=True)
    op.create_index("ix_shows_title", "shows", ["title"])
    op.create_index("ix_shows_tmdb_id", "shows", ["tmdb_id"])

    op.create_table(
        "seasons",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("show_id", sa.Integer(), sa.ForeignKey("shows.id", ondelete="CASCADE"), nullable=False),
        sa.Column("season_number", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(256)),
        sa.Column("overview", sa.Text()),
        sa.Column("poster_path", sa.String(512)),
        sa.Column("air_date", sa.String(10)),
        sa.UniqueConstraint("show_id", "season_number"),
    )
    op.create_index("ix_seasons_show_id", "seasons", ["show_id"])

    op.create_table(
        "episodes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("show_id", sa.Integer(), sa.ForeignKey("shows.id", ondelete="CASCADE"), nullable=False),
        sa.Column("season_number", sa.Integer(), nullable=False),
        sa.Column("episode_number", sa.Integer()),
        sa.Column("episode_end", sa.Integer()),
        sa.Column("title", sa.String(512)),
        sa.Column("overview", sa.Text()),
        sa.Column("still_path", sa.String(512)),
        sa.Column("air_date", sa.String(10)),
        sa.Column("runtime", sa.Integer()),
        sa.Column("tmdb_rating", sa.Float()),
    )
    op.create_index("ix_episodes_show_id", "episodes", ["show_id"])
    op.create_index("ix_episodes_season_number", "episodes", ["season_number"])

    op.add_column("media_files", sa.Column(
        "episode_id", sa.Integer(), sa.ForeignKey("episodes.id", ondelete="CASCADE"), nullable=True))
    op.create_index("ix_media_files_episode_id", "media_files", ["episode_id"])


def downgrade() -> None:
    op.drop_index("ix_media_files_episode_id", table_name="media_files")
    op.drop_column("media_files", "episode_id")
    op.drop_table("episodes")
    op.drop_table("seasons")
    op.drop_table("shows")
