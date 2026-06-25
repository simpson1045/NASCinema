"""Playback decision + streaming endpoints (direct range serve / HLS)."""

from __future__ import annotations

import asyncio
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import MediaFile
from ..playback import decide
from ..streaming import cached_ranges, ensure_segment, get_or_start, log_access

router = APIRouter(prefix="/api", tags=["playback"])


async def _file_and_decision(file_id: int, session: AsyncSession):
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf:
        raise HTTPException(status_code=404, detail="File not found")
    d = decide(
        video_codec=mf.video_codec,
        audio_codec=mf.audio_codec,
        container=mf.container,
        hdr=mf.hdr,
    )
    return mf, d


@router.get("/play/{file_id}")
async def play_decision(
    file_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    _, d = await _file_and_decision(file_id, session)
    url = (
        f"/api/stream/{file_id}/direct"
        if d["mode"] == "direct"
        else f"/api/stream/{file_id}/master.m3u8"
    )
    return {"file_id": file_id, "mode": d["mode"], "reason": d["reason"], "url": url}


@router.get("/stream/{file_id}/direct")
async def stream_direct(
    file_id: int, session: AsyncSession = Depends(get_session)
):
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf or not Path(mf.path).exists():
        raise HTTPException(status_code=404, detail="File not found")
    # Starlette's FileResponse honours Range requests for seeking.
    return FileResponse(mf.path)


@router.get("/stream/{file_id}/master.m3u8")
async def stream_master(
    file_id: int, session: AsyncSession = Depends(get_session)
):
    mf, d = await _file_and_decision(file_id, session)
    if d["mode"] == "direct":
        raise HTTPException(status_code=400, detail="This file is direct-play")
    s = get_or_start(file_id, mf.path, d, mf.duration)
    for _ in range(60):  # wait up to ~30s for the playlist to appear
        if s.playlist.exists() and s.playlist.stat().st_size > 0:
            break
        await asyncio.sleep(0.5)
    if not s.playlist.exists():
        raise HTTPException(status_code=503, detail="Transcode did not start")
    return FileResponse(
        str(s.playlist),
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-cache"},
    )


@router.get("/stream/{file_id}/cached")
async def stream_cached(
    file_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    """Which spans of the film are already converted — for painting the scrubber."""
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf:
        raise HTTPException(status_code=404, detail="File not found")
    return {
        "file_id": file_id,
        "duration": mf.duration,
        "ranges": cached_ranges(file_id),
    }


@router.get("/stream/{file_id}/{segment}")
async def stream_segment(file_id: int, segment: str):
    if (
        not segment.startswith("seg_")
        or not segment.endswith(".ts")
        or "/" in segment
        or "\\" in segment
    ):
        raise HTTPException(status_code=400, detail="Bad segment")
    try:
        seg_index = int(segment[4:-3])
    except ValueError:
        raise HTTPException(status_code=400, detail="Bad segment")
    # Restarts the transcode at this point if it's a forward seek past the head.
    t0 = time.monotonic()
    path, restarted = ensure_segment(file_id, seg_index)
    if path is None:
        raise HTTPException(status_code=404, detail="No active session")
    for _ in range(60):
        if path.exists() and path.stat().st_size > 0:
            log_access(file_id, seg_index, restarted, time.monotonic() - t0)
            return FileResponse(str(path), media_type="video/mp2t")
        await asyncio.sleep(0.5)
    raise HTTPException(status_code=404, detail="Segment not ready")
