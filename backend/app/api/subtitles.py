"""Subtitle search/download (OpenSubtitles) + WebVTT serving.

Phase 1: text subtitles for movies that lack usable ones (most of the library).
Downloaded VTTs are cached locally (not on the evictable transcode cache) since
they're tiny and worth keeping. PGS overlay is a later phase.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import opensubtitles as osub
from ..config import get_settings
from ..db import get_session
from ..models import MediaFile, Movie

router = APIRouter(prefix="/api/subtitles", tags=["subtitles"])


def _subs_dir(file_id: int) -> Path:
    d = Path(get_settings().data_dir) / "subs" / str(file_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


async def _file_and_movie(file_id: int, session: AsyncSession):
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf:
        raise HTTPException(status_code=404, detail="File not found")
    movie = None
    if mf.movie_id:
        movie = await session.scalar(select(Movie).where(Movie.id == mf.movie_id))
    return mf, movie


def _entry(file_id: int, path: Path) -> dict:
    lang = path.stem.split("-")[0]
    return {
        "id": path.stem,
        "lang": lang,
        "label": lang.upper(),
        "url": f"/api/subtitles/{file_id}/file/{path.name}",
    }


@router.get("/{file_id}")
async def list_subtitles(
    file_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    await _file_and_movie(file_id, session)
    subs = [_entry(file_id, p) for p in sorted(_subs_dir(file_id).glob("*.vtt"))]
    return {"file_id": file_id, "subtitles": subs}


@router.get("/{file_id}/search")
async def search_subtitles(
    file_id: int,
    lang: str = "en",
    session: AsyncSession = Depends(get_session),
) -> dict:
    mf, movie = await _file_and_movie(file_id, session)
    if not get_settings().opensubtitles_api_key:
        raise HTTPException(status_code=503, detail="OpenSubtitles not configured")
    moviehash = await asyncio.to_thread(osub.compute_moviehash, mf.path)
    results = await osub.search(
        query=movie.title if movie else None,
        year=movie.year if movie else None,
        languages=lang,
        moviehash=moviehash,
    )
    return {"results": results, "moviehash_matched": bool(moviehash)}


class DownloadReq(BaseModel):
    os_file_id: int
    language: str = "und"


@router.post("/{file_id}/download")
async def download_subtitle(
    file_id: int, req: DownloadReq, session: AsyncSession = Depends(get_session)
) -> dict:
    await _file_and_movie(file_id, session)
    raw = await osub.download_srt(req.os_file_id)
    if not raw:
        raise HTTPException(status_code=502, detail="Subtitle download failed")
    name = f"{req.language}-{req.os_file_id}.vtt"
    path = _subs_dir(file_id) / name
    await asyncio.to_thread(path.write_text, osub.srt_to_vtt(raw), "utf-8")
    return _entry(file_id, path)


@router.get("/{file_id}/file/{name}")
async def serve_subtitle(file_id: int, name: str):
    if not name.endswith(".vtt") or "/" in name or "\\" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Bad name")
    path = _subs_dir(file_id) / name
    if not path.exists():
        raise HTTPException(status_code=404, detail="Subtitle not found")
    data = await asyncio.to_thread(path.read_bytes)
    return Response(content=data, media_type="text/vtt")
