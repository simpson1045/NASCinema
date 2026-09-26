"""A "something's wrong here" flag raised from the couch (controller View
button / F8): what was on screen, which movie or trailer, and where in it —
so problems get reported without stopping to describe them.

movie_id is deliberately not a foreign key: a flag should outlive the library
row it points at (movies get replaced and re-matched).
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Flag(Base):
    __tablename__ = "flags"

    id: Mapped[int] = mapped_column(primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    app_version: Mapped[str | None] = mapped_column(String(32))
    platform: Mapped[str | None] = mapped_column(String(32))
    # Which screen: "bp-home", "bp-movie", "bp-trailer", "player", "library" …
    screen: Mapped[str | None] = mapped_column(String(64))
    # What was playing: "trailer", "movie", "extra" — or NULL (just UI).
    kind: Mapped[str | None] = mapped_column(String(16))
    movie_id: Mapped[int | None] = mapped_column(Integer, index=True)
    movie_title: Mapped[str | None] = mapped_column(String(256))
    media_file_id: Mapped[int | None] = mapped_column(Integer)
    position_seconds: Mapped[float | None] = mapped_column(Float)
    note: Mapped[str | None] = mapped_column(Text)
    context: Mapped[dict | None] = mapped_column(JSON)
    has_screenshot: Mapped[bool] = mapped_column(Boolean, default=False)
    resolved: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    resolution_note: Mapped[str | None] = mapped_column(Text)

    def __repr__(self) -> str:
        return f"<Flag {self.id} {self.screen} {self.movie_title!r} @{self.position_seconds}>"
