"""TV shows API: the show list, one show's seasons + episodes (with files,
tracks and progress), and the shows half of Continue Watching."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import get_session
from ..metadata import get_show_logo
from ..models import Episode, MediaFile, Show, WatchProgress
from ..tracks import quality_label, track_rows, version_label

router = APIRouter(prefix="/api", tags=["shows"])


def _watched(pos: float, dur: float) -> bool:
    """Finished = into the end credits (an episode's are short)."""
    return bool(dur) and (pos >= dur - 60 or pos >= 0.92 * dur)


def _order(e: Episode) -> tuple:
    # Specials (season 0) after the real seasons; unnumbered files by title.
    return (e.season_number == 0, e.season_number,
            e.episode_number if e.episode_number is not None else 10_000,
            e.title or "")


def _show_summary(s: Show, episodes: list[Episode] | None = None) -> dict:
    out = {
        "id": s.id,
        "title": s.title,
        "year": s.year,
        "tmdb_id": s.tmdb_id,
        "overview": s.overview,
        "poster_path": s.poster_path,
        "backdrop_path": s.backdrop_path,
        "genres": s.genres or [],
        "rating": s.rating,
        "certification": s.certification,
        "status": s.status,
        "first_air_date": s.first_air_date,
        "added_at": s.added_at.isoformat() if s.added_at else None,
    }
    if episodes is not None:
        out["season_count"] = len({e.season_number for e in episodes if e.season_number})
        out["episode_count"] = len(episodes)
    return out


def _file(mf: MediaFile) -> dict:
    t = track_rows(mf)
    return {
        "id": mf.id,
        "label": version_label(mf),
        "quality": quality_label(mf),
        "audio_tracks": t["audio"],
        "subtitle_tracks": t["subtitles"],
        "container": mf.container,
        "video_codec": mf.video_codec,
        "audio_codec": mf.audio_codec,
        "width": mf.width,
        "height": mf.height,
        "duration": mf.duration,
        "hdr": mf.hdr,
        "size_bytes": mf.size_bytes,
    }


async def _progress(session: AsyncSession, file_ids: list[int]) -> dict[int, WatchProgress]:
    if not file_ids:
        return {}
    rows = (await session.scalars(
        select(WatchProgress).where(WatchProgress.media_file_id.in_(file_ids)))).all()
    return {w.media_file_id: w for w in rows}


def _episode(e: Episode, progress: dict[int, WatchProgress]) -> dict:
    files = [_file(f) for f in e.files]
    best = None  # the file with the newest progress decides the episode's state
    for f in e.files:
        w = progress.get(f.id)
        if w and (best is None or w.updated_at > best[0].updated_at):
            best = (w, f)
    pos = best[0].position_seconds if best else 0.0
    dur = (best[1].duration if best else (e.files[0].duration if e.files else None)) or 0.0
    return {
        "id": e.id,
        "season_number": e.season_number,
        "episode_number": e.episode_number,
        "episode_end": e.episode_end,
        "title": e.title,
        "overview": e.overview,
        "still_path": e.still_path,
        "air_date": e.air_date,
        "runtime": e.runtime,
        "rating": e.tmdb_rating,
        "files": files,
        "position": pos,
        "duration": dur,
        "watched": _watched(pos, dur),
        "updated_at": best[0].updated_at.isoformat() if best and best[0].updated_at else None,
    }


def _next_up(eps: list[dict]) -> dict | None:
    """Resume the episode in progress; else the one after the last watched;
    else the first. None when everything's watched."""
    touched = [e for e in eps if e["updated_at"]]
    if touched:
        last = max(touched, key=lambda e: e["updated_at"])
        if not last["watched"] and last["position"] >= 30:
            return last
        i = eps.index(last)
        return next((e for e in eps[i + 1:] if not e["watched"]), None)
    return next((e for e in eps if not e["watched"]), None)


async def _load_show(session: AsyncSession, show_id: int) -> Show | None:
    return await session.scalar(
        select(Show).where(Show.id == show_id).options(
            selectinload(Show.seasons),
            selectinload(Show.episodes).selectinload(Episode.files)
            .selectinload(MediaFile.streams)))


@router.get("/shows")
async def list_shows(session: AsyncSession = Depends(get_session)) -> dict:
    shows = (await session.scalars(
        select(Show).options(selectinload(Show.episodes)).order_by(Show.title))).all()
    return {"shows": [_show_summary(s, list(s.episodes)) for s in shows]}


@router.get("/shows/continue")
async def continue_shows(session: AsyncSession = Depends(get_session)) -> dict:
    """Per show you've started: the episode to play next, most recent first."""
    rows = (await session.execute(
        select(WatchProgress, MediaFile)
        .join(MediaFile, WatchProgress.media_file_id == MediaFile.id)
        .where(MediaFile.kind == "episode")
        .order_by(WatchProgress.updated_at.desc()))).all()
    out, seen = [], set()
    for wp, mf in rows:
        ep = await session.get(Episode, mf.episode_id) if mf.episode_id else None
        if not ep or ep.show_id in seen:
            continue
        seen.add(ep.show_id)
        show = await _load_show(session, ep.show_id)
        if not show:
            continue
        eps = sorted(show.episodes, key=_order)
        prog = await _progress(session, [f.id for e in eps for f in e.files])
        rows_ = [_episode(e, prog) for e in eps]
        nxt = _next_up(rows_)
        if nxt:
            out.append({"show": _show_summary(show, eps), "episode": nxt})
        if len(out) >= 20:
            break
    return {"items": out}


@router.get("/shows/{show_id}")
async def get_show(show_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    show = await _load_show(session, show_id)
    if not show:
        raise HTTPException(status_code=404, detail="Show not found")
    eps = sorted(show.episodes, key=_order)
    prog = await _progress(session, [f.id for e in eps for f in e.files])
    rows = [_episode(e, prog) for e in eps]
    counts: dict[int, int] = {}
    for e in rows:
        counts[e["season_number"]] = counts.get(e["season_number"], 0) + 1
    return {
        **_show_summary(show, eps),
        "logo": await get_show_logo(show.tmdb_id) if show.tmdb_id else None,
        "seasons": [
            {"season_number": s.season_number, "name": s.name, "overview": s.overview,
             "poster_path": s.poster_path, "air_date": s.air_date,
             "episode_count": counts.get(s.season_number, 0)}
            for s in sorted(show.seasons, key=lambda s: (s.season_number == 0, s.season_number))
        ],
        "episodes": rows,
        "next_up": _next_up(rows),
    }
