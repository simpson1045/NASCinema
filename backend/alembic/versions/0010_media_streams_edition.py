"""media_streams table (per-track probe data) + media_files.edition

Revision ID: 0010
Revises: 0009
Create Date: 2026-09-13

Per-track rows so the playback decision engine can pick an audio/video track per
client (Roku can pass DD+ Atmos but not TrueHD; DTS core but not DTS:X), and so
the detail screen can list versions and tracks for a manual override. `edition`
is the version label parsed from the filename (4K77, Harmy, Director's Cut …).
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("media_files", sa.Column("edition", sa.String(length=128), nullable=True))
    op.create_table(
        "media_streams",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "media_file_id",
            sa.Integer(),
            sa.ForeignKey("media_files.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("index", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("codec", sa.String(length=32), nullable=True),
        sa.Column("profile", sa.String(length=64), nullable=True),
        sa.Column("language", sa.String(length=16), nullable=True),
        sa.Column("title", sa.String(length=256), nullable=True),
        sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_forced", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("bit_rate", sa.BigInteger(), nullable=True),
        sa.Column("channels", sa.Integer(), nullable=True),
        sa.Column("channel_layout", sa.String(length=32), nullable=True),
        sa.Column("sample_rate", sa.Integer(), nullable=True),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("bit_depth", sa.Integer(), nullable=True),
        sa.Column("frame_rate", sa.Float(), nullable=True),
        sa.Column("hdr_format", sa.String(length=16), nullable=True),
        sa.Column("dv_profile", sa.Integer(), nullable=True),
        sa.UniqueConstraint("media_file_id", "index", name="uq_media_stream_file_index"),
    )
    op.create_index("ix_media_streams_media_file_id", "media_streams", ["media_file_id"])
    op.create_index("ix_media_streams_kind", "media_streams", ["kind"])


def downgrade() -> None:
    op.drop_index("ix_media_streams_kind", table_name="media_streams")
    op.drop_index("ix_media_streams_media_file_id", table_name="media_streams")
    op.drop_table("media_streams")
    op.drop_column("media_files", "edition")
