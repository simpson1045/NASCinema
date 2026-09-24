"""One row per track (video / audio / subtitle) inside a media file.

The playback decision engine and the detail-screen pickers work from these rows:
which audio tracks exist, which one a given client can actually pass through,
what the video's HDR flavour is. `profile` is the ffprobe codec profile string —
it's how DD+ Atmos ("Dolby Digital Plus + Dolby Atmos") is told apart from plain
DD+, and DTS:X ("DTS-HD MA + DTS:X") from DTS-HD MA.
"""

from __future__ import annotations

from sqlalchemy import (
    BigInteger,
    Boolean,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db import Base


class MediaStream(Base):
    __tablename__ = "media_streams"
    __table_args__ = (UniqueConstraint("media_file_id", "index", name="uq_media_stream_file_index"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    media_file_id: Mapped[int] = mapped_column(
        ForeignKey("media_files.id", ondelete="CASCADE"), index=True
    )

    # ffprobe's absolute stream index (what `-map 0:<index>` takes).
    index: Mapped[int] = mapped_column(Integer)
    # 'video' | 'audio' | 'subtitle' (attachments/data streams are not stored).
    kind: Mapped[str] = mapped_column(String(16), index=True)
    codec: Mapped[str | None] = mapped_column(String(32))
    profile: Mapped[str | None] = mapped_column(String(64))
    language: Mapped[str | None] = mapped_column(String(16))
    title: Mapped[str | None] = mapped_column(String(256))
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    is_forced: Mapped[bool] = mapped_column(Boolean, default=False)
    bit_rate: Mapped[int | None] = mapped_column(BigInteger)

    # Audio.
    channels: Mapped[int | None] = mapped_column(Integer)
    channel_layout: Mapped[str | None] = mapped_column(String(32))
    sample_rate: Mapped[int | None] = mapped_column(Integer)

    # Video.
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    bit_depth: Mapped[int | None] = mapped_column(Integer)
    frame_rate: Mapped[float | None] = mapped_column(Float)
    # 'sdr' | 'hdr10' | 'hlg' | 'dolby_vision' (DV carries its profile below).
    hdr_format: Mapped[str | None] = mapped_column(String(16))
    dv_profile: Mapped[int | None] = mapped_column(Integer)

    media_file: Mapped["MediaFile"] = relationship(back_populates="streams")  # noqa: F821

    def __repr__(self) -> str:
        return f"<MediaStream file={self.media_file_id} #{self.index} {self.kind}/{self.codec}>"
