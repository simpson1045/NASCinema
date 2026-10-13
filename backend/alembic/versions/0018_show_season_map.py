"""shows.season_map — per-show TMDB season routing

Revision ID: 0018
Revises: 0017
Create Date: 2026-10-12

Sonarr/TVDB sometimes merges series TMDB keeps apart: "Whose Line Is It
Anyway? (US)" is one folder, seasons 1–21, while TMDB has the 1998 show
(seasons 1–8) and the 2013 revival (seasons 1–13). season_map is a list of
[first_folder_season, tmdb_id, season_offset] — the highest first_season
not above an episode's season decides where its details come from.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("shows", sa.Column("season_map", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("shows", "season_map")
