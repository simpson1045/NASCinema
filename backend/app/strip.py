"""Track Manager strip engine (docs/SPEC-track-manager.md §4) — runs only in
the strip worker, the one process with write access to the movies.

Per job:
  1. Probe the file fresh (not the database) and re-plan it with
     app/track_rules.py; anything no longer strippable is skipped.
  2. ffmpeg stream-copies only the kept tracks (kept audio English-first,
     commentary last; first audio = default; attachments/chapters/metadata
     kept) to the SSD staging dir.
  3. Verify the staged copy: track counts, duration within 15 s, the planned
     default audio first and the only default.
  4. Copy it next to the original as `<name>.stripping`, rename the original
     to `<name>.pre-strip`, rename the new file into place. The original is
     never deleted here — only "Confirm & free space" (a request Matt makes)
     deletes it, and every deletion is logged.
Any failure removes only our own partial files and puts the original back.
"""

from __future__ import annotations

import asyncio
import collections
import json
import os
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import select

from .config import get_settings
from .db import SessionLocal
from .ffmpeg import ffmpeg_path
from .models import MediaFile, Movie, StripJob
from .probe import probe_file
from .scanner import apply_probe
from .strip_cmd import ffmpeg_args, verify
from .track_rules import plan_file

PRE = ".pre-strip"
TMP = ".stripping"
HDD_MARGIN = 20 * 1024 ** 3    # keep 20 GB free on the pool beyond the new copy
# Containers we rewrite, and the muxer for each.
FORMATS = {".mkv": "matroska", ".mp4": "mp4", ".m4v": "mp4"}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def log(msg: str) -> None:
    line = f"{_now().isoformat(timespec='seconds')} {msg}"
    print(line, flush=True)
    try:
        with open(Path(get_settings().data_dir) / "strip.log", "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


# --- the job ------------------------------------------------------------------------

async def _update(job_id: int, **fields) -> None:
    async with SessionLocal() as s:
        job = await s.get(StripJob, job_id)
        for k, v in fields.items():
            setattr(job, k, v)
        await s.commit()


class _Skip(Exception):
    pass


class _Fail(Exception):
    pass


async def run_job(job_id: int) -> None:
    async with SessionLocal() as s:
        job = await s.get(StripJob, job_id)
        mf = await s.get(MediaFile, job.media_file_id)
        movie = await s.get(Movie, mf.movie_id) if mf and mf.movie_id else None
        src = job.path
        protect = bool(movie and movie.track_protect)
        job.status, job.phase, job.progress = "running", "staging", 0.0
        job.started_at, job.error = _now(), None
        await s.commit()
    log(f"job {job_id}: start {src}")
    staged = None
    try:
        staged = await _strip(job_id, src, protect)
    except _Skip as e:
        log(f"job {job_id}: skipped — {e}")
        await _update(job_id, status="skipped", phase=None, error=str(e), finished_at=_now())
    except Exception as e:  # _Fail or anything unexpected: never leave a mess
        _cleanup(job_id, src, staged)
        msg = str(e) if isinstance(e, _Fail) else repr(e)
        log(f"job {job_id}: FAILED — {msg}")
        await _update(job_id, status="failed", phase=None, error=msg, finished_at=_now())


def _staged_path(job_id: int, src: str) -> str:
    return os.path.join(get_settings().strip_dir, f"job{job_id}{Path(src).suffix.lower()}")


def _cleanup(job_id: int, src: str, staged: str | None) -> None:
    """Remove only our own partial files; put the original back if a failure
    landed between the two renames."""
    pre, tmp = src + PRE, src + TMP
    if not os.path.exists(src) and os.path.exists(pre):
        os.rename(pre, src)
        log(f"job {job_id}: original restored from {pre}")
    for p in (tmp, staged or _staged_path(job_id, src)):
        if p and os.path.exists(p):
            os.remove(p)


async def _strip(job_id: int, src: str, protect: bool) -> str | None:
    fmt = FORMATS.get(Path(src).suffix.lower())
    if not fmt:
        raise _Skip(f"{Path(src).suffix} files aren't supported yet")
    if not os.path.exists(src):
        raise _Fail("file not found")
    if os.path.exists(src + PRE):
        raise _Fail("an earlier strip's original (.pre-strip) is still there — confirm or undo it first")

    probe = await probe_file(src)
    if not probe:
        raise _Fail("ffprobe couldn't read the file")
    plan = plan_file(src, probe["duration"], probe["streams"], manual_protect=protect)
    if plan["status"] != "strip":
        raise _Skip({"clean": "already clean", "no_english": "no English audio"}.get(
            plan["status"], plan.get("protected") or plan["status"]))

    size = os.path.getsize(src)
    sdir = get_settings().strip_dir
    os.makedirs(sdir, exist_ok=True)
    if shutil.disk_usage(sdir).free < size * 1.02:
        raise _Fail("not enough space on the SSD staging pool")
    if shutil.disk_usage(os.path.dirname(src)).free < size + HDD_MARGIN:
        raise _Fail("not enough free space on the movie pool to keep the original")
    await _update(job_id, original_bytes=size, savings_est=plan["savings_bytes"])

    # 1. Stream-copy the kept tracks to the SSD.
    staged = _staged_path(job_id, src)
    exe = ffmpeg_path()
    if not exe:
        raise _Fail("ffmpeg not found")
    await _ffmpeg(job_id, ffmpeg_args(exe, src, staged, plan, fmt), probe["duration"])

    # 2. Verify it.
    await _update(job_id, phase="verifying", progress=0.8)
    out = await probe_file(staged)
    why = verify(plan, out, probe["duration"])
    if why:
        raise _Fail(f"verification failed: {why}")

    # 3. Onto the pool next to the original, then swap names.
    await _update(job_id, phase="placing")
    tmp = src + TMP
    await _copy(job_id, staged, tmp)
    st = os.stat(src)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, st.st_mode)
    os.rename(src, src + PRE)
    os.rename(tmp, src)
    os.remove(staged)
    new_size = os.path.getsize(src)
    log(f"job {job_id}: done {size} -> {new_size} bytes; original kept as {src + PRE}")

    # 4. The library's track rows follow the new file. The swap is done, so
    # from here nothing may fail the job (that would strand the .pre-strip).
    note = None
    try:
        fresh = await probe_file(src)
        async with SessionLocal() as s:
            mf = await s.get(MediaFile, (await s.get(StripJob, job_id)).media_file_id)
            if mf and fresh:
                await s.refresh(mf, ["streams"])
                await apply_probe(s, mf, fresh)
                await s.commit()
    except Exception as e:
        note = f"stripped, but refreshing the library's track list failed: {e!r}"
        log(f"job {job_id}: {note}")
    await _update(job_id, status="done", phase=None, progress=1.0, new_bytes=new_size,
                  pre_strip_path=src + PRE, finished_at=_now(), error=note)
    return None


async def _ffmpeg(job_id: int, args: list[str], duration: float | None) -> None:
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    tail: collections.deque[str] = collections.deque(maxlen=20)
    last = 0.0

    async def progress() -> None:
        nonlocal last
        async for raw in proc.stdout:
            line = raw.decode("utf-8", "replace").strip()
            if line.startswith("out_time_us=") and duration:
                try:
                    done = int(line.split("=", 1)[1]) / 1e6
                except ValueError:
                    continue
                if time.monotonic() - last > 5:
                    last = time.monotonic()
                    await _update(job_id, progress=round(min(done / duration, 1.0) * 0.8, 3))

    async def errors() -> None:
        async for raw in proc.stderr:
            tail.append(raw.decode("utf-8", "replace").rstrip())

    await asyncio.gather(progress(), errors())
    if await proc.wait() != 0:
        raise _Fail("ffmpeg failed: " + " | ".join(list(tail)[-4:]))


async def _copy(job_id: int, src: str, dst: str) -> None:
    total = os.path.getsize(src)
    state = {"done": 0}

    def work() -> None:
        with open(src, "rb") as fi, open(dst, "wb") as fo:
            while chunk := fi.read(16 * 1024 * 1024):
                fo.write(chunk)
                state["done"] += len(chunk)
            fo.flush()
            os.fsync(fo.fileno())

    task = asyncio.create_task(asyncio.to_thread(work))
    while not task.done():
        await asyncio.sleep(5)
        await _update(job_id, progress=round(0.8 + 0.2 * state["done"] / max(total, 1), 3))
    await task
    if os.path.getsize(dst) != total:
        raise _Fail("copy to the movie pool came out the wrong size")


# --- undo / confirm (requests from the app) + crash recovery -------------------------

async def handle_requests() -> None:
    async with SessionLocal() as s:
        jobs = (await s.scalars(select(StripJob).where(StripJob.request.is_not(None)))).all()
        ids = [(j.id, j.request) for j in jobs]
    for job_id, req in ids:
        try:
            if req == "confirm":
                await _confirm(job_id)
            elif req == "undo":
                await _undo(job_id)
        except Exception as e:
            log(f"job {job_id}: {req} FAILED — {e!r}")
            await _update(job_id, error=f"{req} failed: {e}")
        await _update(job_id, request=None)


async def _confirm(job_id: int) -> None:
    """Matt pressed "Confirm & free space": delete the kept original."""
    async with SessionLocal() as s:
        job = await s.get(StripJob, job_id)
        if job.status != "done":
            return
        pre = job.pre_strip_path
    if pre and os.path.exists(pre):
        size = os.path.getsize(pre)
        os.remove(pre)
        log(f"job {job_id}: DELETED original {pre} ({size} bytes) — confirmed in the app")
        try:
            with open(Path(get_settings().data_dir) / "strip_deletions.log", "a",
                      encoding="utf-8") as f:
                f.write(json.dumps({"at": _now().isoformat(), "job": job_id,
                                    "path": pre, "bytes": size}) + "\n")
        except OSError:
            pass
    await _update(job_id, status="confirmed", confirmed_at=_now())


async def _undo(job_id: int) -> None:
    """Put the original back over the stripped file."""
    async with SessionLocal() as s:
        job = await s.get(StripJob, job_id)
        if job.status != "done":
            return
        src, pre = job.path, job.pre_strip_path
    if not pre or not os.path.exists(pre):
        raise _Fail("the original isn't there any more")
    os.replace(pre, src)
    log(f"job {job_id}: UNDONE — original back at {src}")
    fresh = await probe_file(src)
    async with SessionLocal() as s:
        job = await s.get(StripJob, job_id)
        mf = await s.get(MediaFile, job.media_file_id)
        if mf and fresh:
            await s.refresh(mf, ["streams"])
            await apply_probe(s, mf, fresh)
        job.status, job.new_bytes = "undone", None
        await s.commit()


async def recover() -> None:
    """Worker start: any job left "running" was interrupted. Put its original
    back if needed, remove our partial files, and fail it (queue it again)."""
    async with SessionLocal() as s:
        jobs = (await s.scalars(select(StripJob).where(StripJob.status == "running"))).all()
        todo = [(j.id, j.path) for j in jobs]
    for job_id, src in todo:
        pre, tmp = src + PRE, src + TMP
        if os.path.exists(pre):
            # Interrupted around the swap: the original wins, always.
            os.replace(pre, src)
            log(f"job {job_id}: recovered — original restored")
        for p in (tmp, _staged_path(job_id, src)):
            if os.path.exists(p):
                os.remove(p)
        await _update(job_id, status="failed", phase=None, finished_at=_now(),
                      error="interrupted (the worker restarted) — original untouched; queue it again")
