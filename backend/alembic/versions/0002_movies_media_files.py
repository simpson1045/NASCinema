"""movies + media_files

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-24
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "movies",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("tmdb_id", sa.Integer(), nullable=True),
        sa.Column("title", sa.String(length=512), nullable=False),
        sa.Column("original_title", sa.String(length=512), nullable=True),
        sa.Column("year", sa.Integer(), nullable=True),
        sa.Column("overview", sa.Text(), nullable=True),
        sa.Column("runtime", sa.Integer(), nullable=True),
        sa.Column("rating", sa.Float(), nullable=True),
        sa.Column("poster_path", sa.String(length=512), nullable=True),
        sa.Column("backdrop_path", sa.String(length=512), nullable=True),
        sa.Column("genres", sa.JSON(), nullable=True),
        sa.Column("match_confidence", sa.Float(), nullable=True),
        sa.Column("locked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "added_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("ix_movies_tmdb_id", "movies", ["tmdb_id"])
    op.create_index("ix_movies_year", "movies", ["year"])

    op.create_table(
        "media_files",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "movie_id",
            sa.Integer(),
            sa.ForeignKey("movies.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("path", sa.String(length=1024), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("container", sa.String(length=32), nullable=True),
        sa.Column("video_codec", sa.String(length=32), nullable=True),
        sa.Column("audio_codec", sa.String(length=32), nullable=True),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("duration", sa.Float(), nullable=True),
        sa.Column("bit_depth", sa.Integer(), nullable=True),
        sa.Column("hdr", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "added_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("probed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_media_files_movie_id", "media_files", ["movie_id"])
    op.create_index("ix_media_files_path", "media_files", ["path"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_media_files_path", table_name="media_files")
    op.drop_index("ix_media_files_movie_id", table_name="media_files")
    op.drop_table("media_files")
    op.drop_index("ix_movies_year", table_name="movies")
    op.drop_index("ix_movies_tmdb_id", table_name="movies")
    op.drop_table("movies")
