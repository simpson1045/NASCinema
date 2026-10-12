"""TV shows: a show, its seasons, and episodes. An episode's files are plain
MediaFile rows (kind='episode', episode_id set), so streaming, resume points,
subtitles and the bitstream audio all work exactly as they do for movies."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Show(Base):
    __tablename__ = "shows"

    id: Mapped[int] = mapped_column(primary_key=True)
    # The show's folder under a show root — the identity across scans.
    folder: Mapped[str] = mapped_column(String(1024), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(512), index=True)
    year: Mapped[int | None] = mapped_column(Integer)
    tmdb_id: Mapped[int | None] = mapped_column(Integer, index=True)
    overview: Mapped[str | None] = mapped_column(Text)
    poster_path: Mapped[str | None] = mapped_column(String(512))
    backdrop_path: Mapped[str | None] = mapped_column(String(512))
    genres: Mapped[list | None] = mapped_column(JSON)
    rating: Mapped[float | None] = mapped_column(Float)
    certification: Mapped[str | None] = mapped_column(String(16))
    status: Mapped[str | None] = mapped_column(String(32))  # Ended / Returning Series
    first_air_date: Mapped[str | None] = mapped_column(String(10))
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)

    seasons: Mapped[list["Season"]] = relationship(
        back_populates="show", cascade="all, delete-orphan", order_by="Season.season_number")
    episodes: Mapped[list["Episode"]] = relationship(
        back_populates="show", cascade="all, delete-orphan")


class Season(Base):
    __tablename__ = "seasons"
    __table_args__ = (UniqueConstraint("show_id", "season_number"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    show_id: Mapped[int] = mapped_column(ForeignKey("shows.id", ondelete="CASCADE"), index=True)
    season_number: Mapped[int] = mapped_column(Integer)  # 0 = Specials; MythBusters uses years
    name: Mapped[str | None] = mapped_column(String(256))
    overview: Mapped[str | None] = mapped_column(Text)
    poster_path: Mapped[str | None] = mapped_column(String(512))
    air_date: Mapped[str | None] = mapped_column(String(10))

    show: Mapped[Show] = relationship(back_populates="seasons")


class Episode(Base):
    __tablename__ = "episodes"

    id: Mapped[int] = mapped_column(primary_key=True)
    show_id: Mapped[int] = mapped_column(ForeignKey("shows.id", ondelete="CASCADE"), index=True)
    season_number: Mapped[int] = mapped_column(Integer, index=True)
    # None when the filename carries no number (loose cartoon shorts) — those
    # get one episode row per file and sort by name.
    episode_number: Mapped[int | None] = mapped_column(Integer)
    episode_end: Mapped[int | None] = mapped_column(Integer)  # S01E01-E02 double episodes
    title: Mapped[str | None] = mapped_column(String(512))
    overview: Mapped[str | None] = mapped_column(Text)
    still_path: Mapped[str | None] = mapped_column(String(512))
    air_date: Mapped[str | None] = mapped_column(String(10))
    runtime: Mapped[int | None] = mapped_column(Integer)  # minutes (TMDB)
    tmdb_rating: Mapped[float | None] = mapped_column(Float)

    show: Mapped[Show] = relationship(back_populates="episodes")
    files: Mapped[list["MediaFile"]] = relationship(  # noqa: F821
        back_populates="episode", order_by="MediaFile.id")
