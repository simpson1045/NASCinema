"""movies.track_protect — Track Manager's "Protect this movie" toggle

Revision ID: 0014
Revises: 0013
Create Date: 2026-09-26

A protected movie is never stripped (on top of the fan-preservation filename
rule in app/track_rules.py). See docs/SPEC-track-manager.md.
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("movies", sa.Column("track_protect", sa.Boolean(),
                                      nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("movies", "track_protect")
