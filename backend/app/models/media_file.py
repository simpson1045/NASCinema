"""A physical media file. One movie can have several (4K HDR + 1080p, etc.).

The probed codec/container/resolution fields are what drive the
Direct Play -> Remux -> Transcode decision later in Phase 1.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class MediaFile(Base):
    __tablename__ = "media_files"

    id: Mapped[int] = mapped_column(primary_key=True)
    movie_id: Mapped[int | None] = mapped_column(
        ForeignKey("movies.id", ondelete="CASCADE"), index=True
    )

    path: Mapped[str] = mapped_column(String(1024), unique=True, index=True)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger)

    # Probed with ffprobe at scan time.
    container: Mapped[str | None] = mapped_column(String(32))
    video_codec: Mapped[str | None] = mapped_column(String(32))
    audio_codec: Mapped[str | None] = mapped_column(String(32))
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    duration: Mapped[float | None] = mapped_column(Float)  # seconds
    bit_depth: Mapped[int | None] = mapped_column(Integer)
    hdr: Mapped[bool] = mapped_column(Boolean, default=False)

    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    probed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    movie: Mapped["Movie | None"] = relationship(back_populates="files")  # noqa: F821

    def __repr__(self) -> str:
        return f"<MediaFile {self.path!r}>"
