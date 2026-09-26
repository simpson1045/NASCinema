"""Track Manager (docs/SPEC-track-manager.md) — Phase A: the plan only.

Works from the scanned track rows in the database; never opens or writes a
media file. The rules live in app/track_rules.py.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import get_session
from ..models import MediaFile, MediaStream, Movie
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


def _row(movie: Movie, mf: MediaFile, plan: dict) -> dict:
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
    }


@router.get("/plan")
async def library_plan(min_savings_mb: float = 0,
                       session: AsyncSession = Depends(get_session)) -> dict:
    """Every feature file the rules would change, biggest savings first, plus
    the ones skipped on purpose (protected / no English audio)."""
    groups: dict[str, list[dict]] = {"strip": [], "protected": [], "no_english": []}
    clean = 0
    for movie, mf in await _feature_files(session):
        plan = _plan(mf, movie)
        if plan["status"] == "clean":
            clean += 1
            continue
        if plan["status"] == "strip" and plan["savings_bytes"] < min_savings_mb * 1e6:
            continue
        groups[plan["status"]].append(_row(movie, mf, plan))
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
    return {**_row(movie, mf, plan), "manual_protect": bool(movie.track_protect),
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
