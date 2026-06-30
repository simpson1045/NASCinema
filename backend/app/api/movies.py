"""Library browse + scan-trigger endpoints.

Auth gating lands with the login flow; for now these are open so the Phase-1
scanner and Flutter grid can be exercised end-to-end.
"""

from __future__ import annotations

import asyncio
from collections import Counter

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import get_session
from ..metadata import get_movie_logo, get_movie_videos
from ..models import MediaFile, Movie
from ..models.watch_progress import WatchProgress
from ..scanner import backfill_ratings, scan
from ..trailers import ensure_trailer, is_cached, trailer_version

router = APIRouter(prefix="/api", tags=["library"])


def _summary(m: Movie) -> dict:
    features = [f for f in m.files if f.kind == "feature"]
    primary = features[0] if features else (m.files[0] if m.files else None)
    return {
        "id": m.id,
        "title": m.title,
        "year": m.year,
        "rating": m.rating,
        "overview": m.overview,
        "poster_path": m.poster_path,
        "backdrop_path": m.backdrop_path,
        "genres": m.genres or [],
        "runtime": m.runtime,
        "tmdb_id": m.tmdb_id,
        "match_confidence": m.match_confidence,
        "locked": m.locked,
        "bluray_url": m.bluray_url,
        "added_at": m.added_at.isoformat() if m.added_at else None,
        "popularity": m.popularity,
        "vote_count": m.vote_count,
        "imdb_rating": m.imdb_rating,
        "rt_score": m.rt_score,
        "metacritic": m.metacritic,
        "collection_id": m.collection_id,
        "collection_name": m.collection_name,
        "file_count": len(features),
        "resolution": (
            f"{primary.width}x{primary.height}"
            if primary and primary.width
            else None
        ),
        "video_codec": primary.video_codec if primary else None,
        "hdr": primary.hdr if primary else False,
    }


@router.get("/movies")
async def list_movies(session: AsyncSession = Depends(get_session)) -> dict:
    result = await session.scalars(
        select(Movie).options(selectinload(Movie.files)).order_by(Movie.title)
    )
    return {"movies": [_summary(m) for m in result.all()]}


@router.get("/home")
async def home(session: AsyncSession = Depends(get_session)) -> dict:
    """The carousel home screen: server-composed rails so the TV client just
    renders. Rails with no content are omitted, so "Popular"/"Top Rated" simply
    don't appear until the ratings backfill has run."""
    movies = (
        await session.scalars(select(Movie).options(selectinload(Movie.files)))
    ).all()
    summ = {m.id: _summary(m) for m in movies}
    rails: list[dict] = []

    def rail(key: str, title: str, ms: list[Movie], limit: int = 25) -> None:
        if ms:
            rails.append(
                {"key": key, "title": title, "movies": [summ[m.id] for m in ms[:limit]]}
            )

    # Continue Watching — in-progress feature files, most-recently-watched first.
    prog = (
        await session.execute(
            select(WatchProgress, MediaFile)
            .join(MediaFile, WatchProgress.media_file_id == MediaFile.id)
            .order_by(WatchProgress.updated_at.desc())
        )
    ).all()
    seen: set[int] = set()
    cw: list[dict] = []
    for wp, mf in prog:
        if mf.movie_id is None or mf.movie_id in seen or mf.movie_id not in summ:
            continue
        pos = wp.position_seconds or 0.0
        dur = mf.duration or 0.0
        if pos < 30:
            continue
        if dur and pos > dur - 120:  # basically finished — don't resurface it
            continue
        item = dict(summ[mf.movie_id])
        item["resume_position"] = pos
        item["resume_file_id"] = mf.id
        cw.append(item)
        seen.add(mf.movie_id)
    if cw:
        rails.append(
            {"key": "continue", "title": "Continue Watching", "movies": cw[:20]}
        )

    # Popular (TMDB popularity) — sparse until the backfill populates it.
    rail(
        "popular",
        "Popular",
        sorted(
            (m for m in movies if m.popularity is not None),
            key=lambda m: m.popularity,
            reverse=True,
        ),
    )

    # Recently Added.
    rail(
        "recent",
        "Recently Added",
        sorted((m for m in movies if m.added_at), key=lambda m: m.added_at, reverse=True),
    )

    # Top Rated — IMDB rating when we have it, else TMDB; ignore thin vote counts.
    def _score(m: Movie) -> float:
        return m.imdb_rating if m.imdb_rating is not None else (m.rating or 0.0)

    rated = [
        m
        for m in movies
        if (m.imdb_rating or m.rating) and (m.vote_count is None or m.vote_count >= 50)
    ]
    rated.sort(key=_score, reverse=True)
    rail("toprated", "Top Rated", rated)

    # Genre rails — the most-represented genres, each by popularity then title.
    counts: Counter = Counter()
    for m in movies:
        for g in m.genres or []:
            counts[g] += 1
    for genre, _n in counts.most_common(8):
        gms = [m for m in movies if genre in (m.genres or [])]
        gms.sort(key=lambda m: (-(m.popularity or 0.0), m.title or ""))
        if len(gms) >= 3:
            rail(f"genre:{genre}", genre, gms)

    # Featured hero — the most popular titles that have a backdrop to show.
    featured_movies = [
        m
        for m in sorted(
            (m for m in movies if m.backdrop_path and m.popularity is not None),
            key=lambda m: m.popularity,
            reverse=True,
        )
    ][:8]
    featured = []
    for m in featured_movies:
        logo = await get_movie_logo(m.tmdb_id) if m.tmdb_id else None
        item = dict(summ[m.id])
        item["logo"] = logo
        # ?v=<mtime> busts the TV's URL cache when the trailer file is re-pulled.
        item["trailer_url"] = f"/api/movies/{m.id}/trailer?v={trailer_version(m.id)}"
        featured.append(item)
        # Warm the trailer cache in the background so it's ready when scrolled to.
        if m.tmdb_id and not is_cached(m.id):
            asyncio.create_task(ensure_trailer(m.id, m.tmdb_id))

    return {"featured": featured, "rails": rails}


@router.get("/movies/{movie_id}")
async def get_movie(
    movie_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    movie = await session.scalar(
        select(Movie).options(selectinload(Movie.files)).where(Movie.id == movie_id)
    )
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    data = _summary(movie)
    data["files"] = [
        {
            "id": f.id,
            "path": f.path,
            "container": f.container,
            "video_codec": f.video_codec,
            "audio_codec": f.audio_codec,
            "width": f.width,
            "height": f.height,
            "duration": f.duration,
            "bit_depth": f.bit_depth,
            "hdr": f.hdr,
            "size_bytes": f.size_bytes,
        }
        for f in movie.files
        if f.kind == "feature"
    ]
    data["extras"] = [
        {
            "id": f.id,
            "title": f.extra_title or "Untitled",
            "type": f.extra_type or "Extra",
            "resolution": f"{f.width}x{f.height}" if f.width else None,
            "duration": f.duration,
            "size_bytes": f.size_bytes,
        }
        for f in movie.files
        if f.kind == "extra"
    ]
    return data


@router.get("/movies/{movie_id}/trailer")
async def movie_trailer(
    movie_id: int, session: AsyncSession = Depends(get_session)
) -> FileResponse:
    """Serve the cached trailer MP4, downloading it via yt-dlp on first request.
    The featured hero plays this. 404 if the movie has no usable trailer."""
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    path = await ensure_trailer(movie_id, movie.tmdb_id)
    if not path:
        raise HTTPException(status_code=404, detail="No trailer available")
    return FileResponse(
        path,
        media_type="video/x-matroska",
        headers={"Cache-Control": "no-cache"},
    )


@router.get("/movies/{movie_id}/videos")
async def movie_videos(
    movie_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    if not movie.tmdb_id:
        return {"videos": []}
    return {"videos": await get_movie_videos(movie.tmdb_id)}


class MovieUpdate(BaseModel):
    bluray_url: str | None = None


@router.patch("/movies/{movie_id}")
async def update_movie(
    movie_id: int,
    body: MovieUpdate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    if body.bluray_url is not None:
        movie.bluray_url = body.bluray_url.strip() or None
    await session.commit()
    return {"id": movie.id, "bluray_url": movie.bluray_url}


class ExtraUpdate(BaseModel):
    title: str | None = None
    type: str | None = None


@router.patch("/extras/{file_id}")
async def update_extra(
    file_id: int,
    body: ExtraUpdate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    mf = await session.scalar(
        select(MediaFile).where(MediaFile.id == file_id, MediaFile.kind == "extra")
    )
    if not mf:
        raise HTTPException(status_code=404, detail="Extra not found")
    if body.title is not None and body.title.strip():
        mf.extra_title = body.title.strip()
    if body.type is not None and body.type.strip():
        mf.extra_type = body.type.strip()
    await session.commit()
    return {"id": mf.id, "title": mf.extra_title, "type": mf.extra_type}


@router.post("/scan")
async def trigger_scan() -> dict:
    # Synchronous for the MVP; becomes a background job with live progress later.
    return await scan()


@router.post("/backfill-ratings")
async def trigger_backfill(limit: int | None = None) -> dict:
    """Populate popularity / external ratings / collection on existing movies.
    Safe to re-run — only touches movies that don't have the data yet."""
    return await backfill_ratings(limit)
