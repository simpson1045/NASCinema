"""Library browse + scan-trigger endpoints.

Auth gating lands with the login flow; for now these are open so the Phase-1
scanner and Flutter grid can be exercised end-to-end.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import get_session
from ..models import Movie
from ..scanner import scan

router = APIRouter(prefix="/api", tags=["library"])


def _summary(m: Movie) -> dict:
    primary = m.files[0] if m.files else None
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
        "file_count": len(m.files),
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
    ]
    return data


@router.post("/scan")
async def trigger_scan() -> dict:
    # Synchronous for the MVP; becomes a background job with live progress later.
    return await scan()
