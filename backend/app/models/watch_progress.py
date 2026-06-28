"""Per-file playback progress: where to resume and which subtitle was on.

Keyed by media_file (one row per file). Multi-user support is a later layer —
a user_id column + a (user_id, media_file_id) key — but the resume itself works
now without it.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class WatchProgress(Base):
    __tablename__ = "watch_progress"

    id: Mapped[int] = mapped_column(primary_key=True)
    media_file_id: Mapped[int] = mapped_column(
        ForeignKey("media_files.id", ondelete="CASCADE"), unique=True, index=True
    )
    position_seconds: Mapped[float] = mapped_column(Float, default=0.0)
    # Subtitle id (the backend subtitle "id" = file stem) the user had on, or
    # NULL = subtitles off.
    subtitle_id: Mapped[str | None] = mapped_column(String(128))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    def __repr__(self) -> str:
        return f"<WatchProgress file={self.media_file_id} @{self.position_seconds:.0f}s>"
