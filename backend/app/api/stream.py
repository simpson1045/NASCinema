"""Playback decision + streaming endpoints (direct range serve / HLS)."""

from __future__ import annotations

import asyncio
import mimetypes
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..metadata import get_movie_logo
from ..models import MediaFile, Movie
from ..models.watch_progress import WatchProgress
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


async def _file_and_decision(
    file_id: int, session: AsyncSession, client: str = "web"
):
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf:
        raise HTTPException(status_code=404, detail="File not found")
    d = decide(
        video_codec=mf.video_codec,
        audio_codec=mf.audio_codec,
        container=mf.container,
        hdr=mf.hdr,
        client=client,
    )
    return mf, d


@router.get("/play/{file_id}")
async def play_decision(
    file_id: int,
    client: str = "web",
    session: AsyncSession = Depends(get_session),
) -> dict:
    # `client` declares playback capability: "web" (browser caps) or "native"
    # (libmpv — direct-plays everything). The native ELKO renderer sends native.
    mf, d = await _file_and_decision(file_id, session, client)
    url = (
        f"/api/stream/{file_id}/direct"
        if d["mode"] == "direct"
        else f"/api/stream/{file_id}/master.m3u8"
    )
    # Artwork for the cast receiver's now-playing screen (absolute TMDB URLs the
    # Chromecast can fetch directly): a backdrop and the clearlogo (fetched +
    # cached on first play; the receiver shows it in place of the title text).
    backdrop = None
    logo = None
    if mf.movie_id:
        mv = await session.scalar(select(Movie).where(Movie.id == mf.movie_id))
        if mv:
            if mv.backdrop_path:
                backdrop = f"https://image.tmdb.org/t/p/w1280{mv.backdrop_path}"
            if mv.tmdb_id:
                logo = await get_movie_logo(mv.tmdb_id)
    # Where to resume + which subtitle was on (0 / null when fresh).
    prog = await session.scalar(
        select(WatchProgress).where(WatchProgress.media_file_id == file_id)
    )
    resume_position = prog.position_seconds if prog else 0.0
    resume_subtitle = prog.subtitle_id if prog else None
    # Probed source facts for the "stats for nerds" overlay.
    return {
        "file_id": file_id,
        "mode": d["mode"],
        "reason": d["reason"],
        "url": url,
        "backdrop": backdrop,
        "logo": logo,
        "resume_position": resume_position,
        "resume_subtitle": resume_subtitle,
        "source": {
            "container": mf.container,
            "video_codec": mf.video_codec,
            "audio_codec": mf.audio_codec,
            "width": mf.width,
            "height": mf.height,
            "bit_depth": mf.bit_depth,
            "hdr": mf.hdr,
            "duration": mf.duration,
            "size_bytes": mf.size_bytes,
        },
    }


# 4 MiB reads: big sequential SMB reads stream the file at full disk speed and
# stay stable — the way a real player reading the NAS file directly does. The
# 64 KiB chunks Starlette's FileResponse uses fire ~850k tiny SMB round-trips on
# a 52 GB REMUX and stall under load. (Proven: VLC opening the NAS file directly
# plays flawlessly; the identical file through FileResponse stutters.)
_STREAM_CHUNK = 4 * 1024 * 1024


@router.get("/stream/{file_id}/direct")
async def stream_direct(
    file_id: int,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    mf = await session.scalar(select(MediaFile).where(MediaFile.id == file_id))
    if not mf or not Path(mf.path).exists():
        raise HTTPException(status_code=404, detail="File not found")

    path = mf.path
    size = await asyncio.to_thread(lambda: Path(path).stat().st_size)
    ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"

    # Parse the Range header ourselves so we control the read block size.
    start, end, status = 0, size - 1, 200
    rng = request.headers.get("range")
    if rng and rng.startswith("bytes="):
        try:
            s, _, e = rng.split("=", 1)[1].split(",")[0].strip().partition("-")
            if s == "" and e:  # suffix range: last N bytes
                start, end = max(0, size - int(e)), size - 1
            else:
                start = int(s) if s else 0
                end = int(e) if e else size - 1
        except ValueError:
            start, end = 0, size - 1
        if start > end or start >= size:
            return Response(
                status_code=416, headers={"Content-Range": f"bytes */{size}"}
            )
        status = 206

    length = end - start + 1

    async def _body():
        # Raw (unbuffered) handle + big reads = few large SMB ops, off the event
        # loop via to_thread so nothing else on the loop starves the stream.
        f = await asyncio.to_thread(open, path, "rb", 0)
        remaining = length
        try:
            await asyncio.to_thread(f.seek, start)
            while remaining > 0:
                chunk = await asyncio.to_thread(
                    f.read, min(_STREAM_CHUNK, remaining)
                )
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk
        finally:
            await asyncio.to_thread(f.close)

    headers = {
        "Accept-Ranges": "bytes",
        "Content-Length": str(length),
        "Content-Type": ctype,
    }
    if status == 206:
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    return StreamingResponse(_body(), status_code=status, headers=headers)


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
