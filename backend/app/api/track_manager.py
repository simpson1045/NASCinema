"""Track Manager (docs/SPEC-track-manager.md).

The plan works from the scanned track rows in the database. Strips are queued
here as strip_jobs rows and carried out by the strip worker (app/strip.py,
its own container) — this process never opens or writes a media file. Undo
and "Confirm & free space" are requests the worker carries out. The rules
live in app/track_rules.py.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..config import get_settings
from ..db import get_session
from ..models import MediaFile, MediaStream, Movie, StripJob
from ..track_rules import plan_file
from ..tracks import _SUB_CODECS, _audio_codec, _channels, lang_name, quality_label

router = APIRouter(prefix="/api/track-manager", tags=["track-manager"])


def _stream(st: MediaStream) -> dict:
    return {
        "index": st.index, "kind": st.kind, "codec": st.codec,
        "language": st.language, "title": st.title,
        "is_default": bool(st.is_default), "is_forced": bool(st.is_forced),
        "bit_rate": st.bit_rate, "channels": st.channels,
    }


def _describe(st: MediaStream) -> str:
    """'Russian · AC-3 5.1 · "MVO"' — how a track reads in the lists."""
    if st.kind == "audio":
        parts = [lang_name(st.language) or "Untagged", _audio_codec(st), _channels(st)]
    elif st.kind == "subtitle":
        codec = _SUB_CODECS.get((st.codec or "").lower(), (st.codec or "").upper())
        parts = [lang_name(st.language) or "Untagged", codec,
                 "Forced" if st.is_forced else ""]
    else:
        parts = [(st.codec or "").upper(), f"{st.width}×{st.height}" if st.width else ""]
    out = " · ".join(p for p in parts if p)
    if st.title:
        out += f' · "{st.title}"'
    return out


def _plan(mf: MediaFile, movie: Movie) -> dict:
    return plan_file(mf.path, mf.duration, [_stream(s) for s in mf.streams],
                     manual_protect=bool(movie.track_protect))


async def _feature_files(session: AsyncSession) -> list[tuple[Movie, MediaFile]]:
    movies = (await session.scalars(
        select(Movie).options(selectinload(Movie.files).selectinload(MediaFile.streams))
    )).all()
    return [(m, f) for m in movies for f in m.files if f.kind == "feature"]


# A job that still "owns" its file: waiting, running, or stripped but not
# yet confirmed/undone.
_ACTIVE = ("queued", "running", "done")


async def _active_jobs(session: AsyncSession) -> dict[int, StripJob]:
    jobs = (await session.scalars(
        select(StripJob).where(StripJob.status.in_(_ACTIVE)).order_by(StripJob.id))).all()
    return {j.media_file_id: j for j in jobs}


def _job_brief(j: StripJob | None) -> dict | None:
    if not j:
        return None
    return {"id": j.id, "status": j.status, "phase": j.phase, "progress": j.progress}


def _row(movie: Movie, mf: MediaFile, plan: dict, job: StripJob | None = None) -> dict:
    by_index = {s.index: s for s in mf.streams}
    return {
        "file_id": mf.id,
        "movie_id": movie.id,
        "title": movie.title,
        "year": movie.year,
        "poster_path": movie.poster_path,
        "quality": quality_label(mf),
        "size_bytes": mf.size_bytes,
        "status": plan["status"],
        "protected": plan["protected"],
        "savings_bytes": plan["savings_bytes"],
        "savings_partial": plan["savings_partial"],
        "drop_count": plan["drop_count"],
        "foreign_default": plan["foreign_default"],
        "dropped": [_describe(by_index[r["index"]]) for r in plan["streams"]
                    if not r["keep"]],
        "job": _job_brief(job),
    }


@router.get("/plan")
async def library_plan(min_savings_mb: float = 0,
                       session: AsyncSession = Depends(get_session)) -> dict:
    """Every feature file the rules would change, biggest savings first, plus
    the ones skipped on purpose (protected / no English audio)."""
    groups: dict[str, list[dict]] = {"strip": [], "protected": [], "no_english": []}
    clean = 0
    active = await _active_jobs(session)
    for movie, mf in await _feature_files(session):
        plan = _plan(mf, movie)
        if plan["status"] == "clean":
            clean += 1
            continue
        if plan["status"] == "strip" and plan["savings_bytes"] < min_savings_mb * 1e6:
            continue
        groups[plan["status"]].append(_row(movie, mf, plan, active.get(mf.id)))
    for rows in groups.values():
        rows.sort(key=lambda r: (r["savings_bytes"], r["drop_count"]), reverse=True)
    return {
        "totals": {
            "strip": len(groups["strip"]),
            "savings_bytes": sum(r["savings_bytes"] for r in groups["strip"]),
            "foreign_default": sum(1 for r in groups["strip"] if r["foreign_default"]),
            "protected": len(groups["protected"]),
            "no_english": len(groups["no_english"]),
            "clean": clean,
        },
        **groups,
    }


@router.get("/file/{file_id}")
async def file_plan(file_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    """One file's full plan: every track, keep/drop and why."""
    mf = await session.scalar(
        select(MediaFile).options(selectinload(MediaFile.streams))
        .where(MediaFile.id == file_id))
    if not mf or not mf.movie_id:
        raise HTTPException(status_code=404, detail="File not found")
    movie = await session.scalar(select(Movie).where(Movie.id == mf.movie_id))
    plan = _plan(mf, movie)
    by_index = {s.index: s for s in mf.streams}
    for r in plan["streams"]:
        r["label"] = _describe(by_index[r["index"]])
    job = (await _active_jobs(session)).get(mf.id)
    return {**_row(movie, mf, plan, job), "manual_protect": bool(movie.track_protect),
            "audio_order": plan["audio_order"],
            "new_default_audio": plan["new_default_audio"],
            "streams": plan["streams"]}


class ProtectReq(BaseModel):
    protected: bool


@router.put("/protect/{movie_id}")
async def set_protect(movie_id: int, req: ProtectReq,
                      session: AsyncSession = Depends(get_session)) -> dict:
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    movie.track_protect = req.protected
    await session.commit()
    return {"movie_id": movie_id, "protected": req.protected}


# --- Phase B: strips ------------------------------------------------------------

# "Strip all" skips files where rewriting a whole remux would save next to
# nothing (a stray subtitle) — unless the movie starts in a foreign language.
STRIP_ALL_MIN_BYTES = 100 * 1000 * 1000


class StripReq(BaseModel):
    file_ids: list[int] | None = None   # None = every worthwhile file ("Strip all")


@router.post("/strip")
async def queue_strip(req: StripReq, session: AsyncSession = Depends(get_session)) -> dict:
    """Queue strips. The worker re-checks each file against a fresh probe
    before touching it."""
    active = await _active_jobs(session)
    queued, skipped = [], []
    for movie, mf in await _feature_files(session):
        if req.file_ids is not None and mf.id not in req.file_ids:
            continue
        plan = _plan(mf, movie)
        if plan["status"] != "strip":
            if req.file_ids is not None:
                skipped.append({"file_id": mf.id, "title": movie.title, "why": plan["status"]})
            continue
        if mf.id in active:
            skipped.append({"file_id": mf.id, "title": movie.title,
                            "why": f"already {active[mf.id].status}"})
            continue
        if (req.file_ids is None and plan["savings_bytes"] < STRIP_ALL_MIN_BYTES
                and not plan["foreign_default"]):
            continue
        session.add(StripJob(media_file_id=mf.id, movie_id=movie.id, path=mf.path,
                             status="queued", savings_est=plan["savings_bytes"],
                             original_bytes=mf.size_bytes))
        queued.append({"file_id": mf.id, "title": movie.title,
                       "savings_bytes": plan["savings_bytes"]})
    await session.commit()
    return {"queued": queued, "skipped": skipped}


def _worker_state() -> dict:
    try:
        d = json.loads((Path(get_settings().data_dir) / "strip_worker.json").read_text())
    except (OSError, ValueError):
        return {"alive": False, "state": "offline"}
    d["alive"] = time.time() - d.get("ts", 0) < 90
    if not d["alive"]:
        d["state"] = "offline"
    return d


@router.get("/jobs")
async def list_jobs(session: AsyncSession = Depends(get_session)) -> dict:
    jobs = (await session.scalars(
        select(StripJob).order_by(StripJob.id.desc()).limit(200))).all()
    titles = {m.id: (m.title, m.year, m.poster_path) for m in (await session.scalars(
        select(Movie).where(Movie.id.in_({j.movie_id for j in jobs if j.movie_id})))).all()}
    rows = []
    for j in jobs:
        t = titles.get(j.movie_id, (j.path.rsplit("/", 1)[-1], None, None))
        rows.append({
            "id": j.id, "file_id": j.media_file_id, "movie_id": j.movie_id,
            "title": t[0], "year": t[1], "poster_path": t[2],
            "status": j.status, "phase": j.phase, "progress": j.progress,
            "request": j.request, "error": j.error,
            "savings_est": j.savings_est, "original_bytes": j.original_bytes,
            "new_bytes": j.new_bytes,
            "created_at": j.created_at.isoformat() if j.created_at else None,
            "finished_at": j.finished_at.isoformat() if j.finished_at else None,
        })
    done = [j for j in jobs if j.status == "done"]
    return {
        "worker": _worker_state(),
        "totals": {
            "queued": sum(1 for j in jobs if j.status == "queued"),
            "running": sum(1 for j in jobs if j.status == "running"),
            "awaiting_confirm": len(done),
            # What "Confirm & free space" frees: the kept originals.
            "confirm_frees_bytes": sum(j.original_bytes or 0 for j in done),
            "saved_bytes": sum((j.original_bytes or 0) - (j.new_bytes or 0)
                               for j in jobs if j.status in ("done", "confirmed")),
        },
        "jobs": rows,
    }


async def _job(session: AsyncSession, job_id: int) -> StripJob:
    job = await session.get(StripJob, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(job_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    job = await _job(session, job_id)
    if job.status != "queued":
        raise HTTPException(status_code=409, detail=f"Job is {job.status}, not queued")
    job.status = "cancelled"
    await session.commit()
    return {"id": job_id, "status": "cancelled"}


@router.post("/jobs/{job_id}/undo")
async def undo_job(job_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    """Put the original back (the worker does it within seconds)."""
    job = await _job(session, job_id)
    if job.status != "done":
        raise HTTPException(status_code=409, detail=f"Job is {job.status} — only a finished, "
                            "unconfirmed strip can be undone")
    job.request = "undo"
    await session.commit()
    return {"id": job_id, "request": "undo"}


class ConfirmReq(BaseModel):
    job_ids: list[int] | None = None   # None = every finished strip


@router.post("/confirm")
async def confirm_jobs(req: ConfirmReq, session: AsyncSession = Depends(get_session)) -> dict:
    """"Confirm & free space": the worker deletes the kept originals of these
    finished strips. The only path that deletes anything, and only on this
    explicit request from the app."""
    q = select(StripJob).where(StripJob.status == "done")
    if req.job_ids is not None:
        q = q.where(StripJob.id.in_(req.job_ids))
    jobs = (await session.scalars(q)).all()
    for j in jobs:
        j.request = "confirm"
    await session.commit()
    return {"confirming": [j.id for j in jobs],
            "frees_bytes": sum(j.original_bytes or 0 for j in jobs)}
