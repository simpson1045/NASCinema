"""Library browse + scan-trigger endpoints.

Auth gating lands with the login flow; for now these are open so the Phase-1
scanner and Flutter grid can be exercised end-to-end.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import get_session
from ..metadata import get_movie_videos
from ..models import MediaFile, Movie
from ..scanner import scan

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
