"""A movie — the logical title, independent of how many files back it."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Movie(Base):
    __tablename__ = "movies"

    id: Mapped[int] = mapped_column(primary_key=True)
    tmdb_id: Mapped[int | None] = mapped_column(Integer, index=True)

    title: Mapped[str] = mapped_column(String(512))
    original_title: Mapped[str | None] = mapped_column(String(512))
    year: Mapped[int | None] = mapped_column(Integer, index=True)
    overview: Mapped[str | None] = mapped_column(Text)
    runtime: Mapped[int | None] = mapped_column(Integer)  # minutes
    rating: Mapped[float | None] = mapped_column(Float)  # TMDB vote average
    poster_path: Mapped[str | None] = mapped_column(String(512))
    backdrop_path: Mapped[str | None] = mapped_column(String(512))
    genres: Mapped[list | None] = mapped_column(JSON, default=list)

    # Ranking signals for home-screen rails. popularity/vote_count come free with
    # the TMDB details fetch; the external scores need an OMDb key (else null).
    popularity: Mapped[float | None] = mapped_column(Float)  # TMDB trending score
    vote_count: Mapped[int | None] = mapped_column(Integer)  # TMDB vote count
    imdb_id: Mapped[str | None] = mapped_column(String(32), index=True)
    imdb_rating: Mapped[float | None] = mapped_column(Float)  # OMDb (0–10)
    # Content rating in settings.rating_region (PG-13, R …); "" = none
    # published, NULL = not looked up yet.
    certification: Mapped[str | None] = mapped_column(String(16))
    rt_score: Mapped[int | None] = mapped_column(Integer)  # OMDb Tomatometer (%)
    metacritic: Mapped[int | None] = mapped_column(Integer)  # OMDb Metascore (0–100)

    # TMDB collection (series) — powers "grouped by franchise" rails.
    collection_id: Mapped[int | None] = mapped_column(Integer, index=True)
    collection_name: Mapped[str | None] = mapped_column(String(512))

    # A pinned Blu-ray.com release page (the exact pressing) — referenced when
    # naming bonus features.
    bluray_url: Mapped[str | None] = mapped_column(String(1024))

    # Manual clearlogo override (full image URL). TMDB can't distinguish e.g. the
    # US "Sorcerer's" from the UK "Philosopher's" logo, so this pins the right one.
    logo_url: Mapped[str | None] = mapped_column(String(1024))

    # Manual trailer override (YouTube URL or key) when TMDB's auto-pick is a poor
    # upload. Blank = use the auto-selected trailer.
    trailer_youtube: Mapped[str | None] = mapped_column(String(256))

    # How confident the match was (for the low-confidence review queue).
    match_confidence: Mapped[float | None] = mapped_column(Float)
    # A manual match the user locked in — must survive rescans (the thing
    # Jellyfin nukes). See README "Design principles".
    locked: Mapped[bool] = mapped_column(Boolean, default=False)

    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    files: Mapped[list["MediaFile"]] = relationship(  # noqa: F821
        back_populates="movie", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Movie {self.title!r} ({self.year})>"
