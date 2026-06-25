"""Playback decision + streaming endpoints (direct range serve / HLS)."""

from __future__ import annotations

import asyncio
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import MediaFile
from ..playback import decide
from ..streaming import cached_ranges, ensure_segment, get_or_start, log_access

router = APIRouter(prefix="/api", tags=["playback"])


def _read_ready_segment(path: Path) -> bytes | None:
    """Read a finished segment in one shot, or None if it isn't ready yet.
    One read (no preceding stat) — `temp_file` muxing means the file only appears
    once complete, so a successful read implies readiness. A single bulk read
    also beats FileResponse's 64 KB chunked streaming over SMB by ~10x."""
    try:
        data = path.read_bytes()
        return data or None
    except OSError:
        return None


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
    s = await asyncio.to_thread(get_or_start, file_id, mf.path, d, mf.duration)
    # VOD pre-writes the playlist synchronously, so the read succeeds on the
    # first try — no poll. Only copy/remux (ffmpeg writes it) needs to wait.
    data = await asyncio.to_thread(_read_ready_segment, s.playlist)
    for _ in range(60):
        if data is not None:
            break
        await asyncio.sleep(0.5)
        data = await asyncio.to_thread(_read_ready_segment, s.playlist)
    if data is None:
        raise HTTPException(status_code=503, detail="Transcode did not start")
    return Response(
        content=data,
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
    ranges = await asyncio.to_thread(cached_ranges, file_id)
    return {
        "file_id": file_id,
        "duration": mf.duration,
        "ranges": ranges,
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
    path, restarted = await asyncio.to_thread(ensure_segment, file_id, seg_index)
    if path is None:
        raise HTTPException(status_code=404, detail="No active session")
    for _ in range(60):
        data = await asyncio.to_thread(_read_ready_segment, path)
        if data is not None:
            log_access(file_id, seg_index, restarted, time.monotonic() - t0)
            return Response(content=data, media_type="video/mp2t")
        await asyncio.sleep(0.5)
    raise HTTPException(status_code=404, detail="Segment not ready")
