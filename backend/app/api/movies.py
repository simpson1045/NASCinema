"""Library browse + scan-trigger endpoints.

Auth gating lands with the login flow; for now these are open so the Phase-1
scanner and Flutter grid can be exercised end-to-end.
"""

from __future__ import annotations

import asyncio
import random
import re
from collections import Counter

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import apple_trailers
from ..db import SessionLocal, get_session
from ..metadata import (
    CURATED,
    franchise_name,
    get_company_logo,
    get_collection_art,
    get_franchise_logo,
    get_movie_logo_info,
    get_related,
    get_movie_videos,
    logo_subtitle,
)
from ..tracks import quality_label, track_rows, version_label
from ..models import MediaFile, Movie
from ..models.watch_progress import WatchProgress
from ..models.watchlist import WatchlistItem
from ..scanner import (
    backfill_certifications,
    backfill_ratings,
    backfill_universes,
    reprobe,
    scan,
    scan_state,
    start_background_scan,
)
from ..trailers import (
    fill_state,
    start_fill,
    clear_trailer,
    ensure_trailer,
    is_cached,
    measure_bars,
    serve_file,
    trailer_bars,
    trailer_source,
    trailer_version,
    upgrade_to_apple,
)

router = APIRouter(prefix="/api", tags=["library"])


def _track_fields(f: MediaFile) -> dict:
    t = track_rows(f)
    return {"audio_tracks": t["audio"], "subtitle_tracks": t["subtitles"]}


async def _logo_fields(m: Movie) -> dict:
    """`logo` (manual override wins, else TMDB's), plus `logo_subtitle` when
    the logo is the franchise's shared wordmark — the apps print it under the
    logo so a sequel still reads as itself ("VIII · The Big Freeze")."""
    if m.logo_url:
        return {"logo": m.logo_url, "logo_subtitle": None}
    if not m.tmdb_id:
        return {"logo": None, "logo_subtitle": None}
    info = await get_movie_logo_info(m.tmdb_id)
    sub = logo_subtitle(m.title, m.collection_name) if info["series"] else None
    return {"logo": info["url"], "logo_subtitle": sub}


_QUALITY_ONLY = re.compile(
    r"^\[?\s*(4k|uhd|remux|hdr|sdr|dv|dolby vision|streaming|web|blu-?ray|"
    r"1080p|2160p|720p|\s|-)+\]?$", re.IGNORECASE)


def _cut_rank(f: MediaFile) -> int:
    """Theatrical first, then no label / a quality-only label ("[4K UHD Remux]",
    "[SDR Streaming]"), then other cuts (Extended, Open Matte, Director's Cut) —
    a plain Play gets the cut people expect (LOTR, GBU, Patriot, Phantasm)."""
    ed = (f.edition or "").strip()
    if "theatrical" in ed.lower():
        return 0
    if not ed or _QUALITY_ONLY.match(ed):
        return 1
    return 2


def _features(files) -> list[MediaFile]:
    """Versions in play order: files we could never probe last (maybe broken),
    then cut rank, then best quality (4K HDR > 4K > 1080p; an "SDR" label after
    its HDR twin — the hdr flag doesn't always tell them apart)."""
    return sorted(
        (f for f in files if f.kind == "feature"),
        key=lambda f: (f.height is None,
                       _cut_rank(f),
                       -max(f.height or 0, round((f.width or 0) * 9 / 16)),
                       not f.hdr,
                       "sdr" in (f.edition or "").lower()),
    )


def _summary(m: Movie) -> dict:
    features = _features(m.files)
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
        "bluray_url": m.bluray_url,
        "trailer_youtube": m.trailer_youtube,
        "added_at": m.added_at.isoformat() if m.added_at else None,
        "popularity": m.popularity,
        "vote_count": m.vote_count,
        "imdb_rating": m.imdb_rating,
        "rt_score": m.rt_score,
        "certification": m.certification or None,
        "metacritic": m.metacritic,
        "collection_id": m.collection_id,
        "collection_name": m.collection_name,
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


@router.get("/home")
async def home(session: AsyncSession = Depends(get_session)) -> dict:
    """The carousel home screen: server-composed rails so the TV client just
    renders. Rails with no content are omitted, so "Popular"/"Top Rated" simply
    don't appear until the ratings backfill has run."""
    movies = (
        await session.scalars(select(Movie).options(selectinload(Movie.files)))
    ).all()
    summ = {m.id: _summary(m) for m in movies}
    # Every tile knows whether its trailer is cached (+ its letterbox bars), so
    # the big picture hero can play the highlighted movie's trailer without
    # ever triggering a download.
    for mid, item in summ.items():
        if is_cached(mid):
            item["trailer_ready"] = True
            item["trailer_url"] = f"/api/movies/{mid}/trailer?v={trailer_version(mid)}"
            item["trailer_bars"] = trailer_bars(mid)
    rails: list[dict] = []

    def rail(key: str, title: str, ms: list[Movie], limit: int = 25) -> None:
        if ms:
            rails.append(
                {"key": key, "title": title, "movies": [summ[m.id] for m in ms[:limit]]}
            )

    # Continue Watching — in-progress feature files, most-recently-watched first.
    prog = (
        await session.execute(
            select(WatchProgress, MediaFile)
            .join(MediaFile, WatchProgress.media_file_id == MediaFile.id)
            .order_by(WatchProgress.updated_at.desc())
        )
    ).all()
    seen: set[int] = set()
    cw: list[dict] = []
    for wp, mf in prog:
        if mf.movie_id is None or mf.movie_id in seen or mf.movie_id not in summ:
            continue
        pos = wp.position_seconds or 0.0
        dur = mf.duration or 0.0
        if pos < 30:
            continue
        if dur and pos > dur - 120:  # basically finished — don't resurface it
            continue
        item = dict(summ[mf.movie_id])
        item["resume_position"] = pos
        item["resume_file_id"] = mf.id
        cw.append(item)
        seen.add(mf.movie_id)
    if cw:
        rails.append(
            {"key": "continue", "title": "Continue Watching", "movies": cw[:20]}
        )

    # My List — saved to watch later, newest first.
    saved = (await session.scalars(
        select(WatchlistItem).order_by(WatchlistItem.added_at.desc())
    )).all()
    mine = [summ[w.movie_id] for w in saved if w.movie_id in summ]
    if mine:
        rails.append({"key": "mylist", "title": "My List", "movies": mine[:40]})

    # Popular (TMDB popularity) — sparse until the backfill populates it.
    rail(
        "popular",
        "Popular",
        sorted(
            (m for m in movies if m.popularity is not None),
            key=lambda m: m.popularity,
            reverse=True,
        ),
    )

    # Recently Added.
    rail(
        "recent",
        "Recently Added",
        sorted((m for m in movies if m.added_at), key=lambda m: m.added_at, reverse=True),
    )

    # Top Rated — IMDB rating when we have it, else TMDB; ignore thin vote counts.
    def _score(m: Movie) -> float:
        return m.imdb_rating if m.imdb_rating is not None else (m.rating or 0.0)

    rated = [
        m
        for m in movies
        if (m.imdb_rating or m.rating) and (m.vote_count is None or m.vote_count >= 50)
    ]
    rated.sort(key=_score, reverse=True)
    rail("toprated", "Top Rated", rated)

    # Genre rails — the most-represented genres, each by popularity then title.
    counts: Counter = Counter()
    for m in movies:
        for g in m.genres or []:
            counts[g] += 1
    for genre, _n in counts.most_common(8):
        gms = [m for m in movies if genre in (m.genres or [])]
        gms.sort(key=lambda m: (-(m.popularity or 0.0), m.title or ""))
        if len(gms) >= 3:
            rail(f"genre:{genre}", genre, gms)

    # Featured hero — a random handful from EVERY movie that has a cached
    # trailer (and a backdrop), so the whole library rotates through the hero.
    # Falls back to the most popular titles until enough trailers exist.
    pool = [m for m in movies if m.backdrop_path and is_cached(m.id)]
    if len(pool) < 8:
        pool = sorted(
            (m for m in movies if m.backdrop_path and m.popularity is not None),
            key=lambda m: m.popularity,
            reverse=True,
        )[:30]
    featured_movies = random.sample(pool, min(8, len(pool)))
    featured = []
    for m in featured_movies:
        item = dict(summ[m.id])
        item.update(await _logo_fields(m))
        # ?v=<mtime> busts the TV's URL cache when the trailer file is re-pulled.
        item["trailer_url"] = f"/api/movies/{m.id}/trailer?v={trailer_version(m.id)}"
        # The banner only plays a trailer that's already cached — never waits on a
        # cold download (which would hang the video while it pulls).
        item["trailer_ready"] = is_cached(m.id)
        # Letterbox bars baked into the trailer ({"top","bottom"} fractions), so
        # the TV can slide it instead of cropping; measured once in the background.
        item["trailer_bars"] = trailer_bars(m.id)
        if item["trailer_ready"] and item["trailer_bars"] is None:
            asyncio.create_task(measure_bars(m.id))
        featured.append(item)
        # Warm the trailer cache in the background so it's ready when scrolled to.
        if (m.tmdb_id or m.trailer_youtube) and not is_cached(m.id):
            asyncio.create_task(
                ensure_trailer(m.id, m.tmdb_id, m.trailer_youtube, m.title, m.year)
            )

    return {"featured": featured, "rails": rails,
            "collections": await _collections(movies, summ, curated=True)}


@router.get("/movies/{movie_id}")
async def get_movie(
    movie_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    movie = await session.scalar(
        select(Movie)
        .options(selectinload(Movie.files).selectinload(MediaFile.streams))
        .where(Movie.id == movie_id)
    )
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    data = _summary(movie)
    # Versions in play order (see _features) so a plain Play gets the right
    # cut in the best copy; each carries its label and tracks for the pickers.
    features = _features(movie.files)
    data["files"] = [
        {
            "id": f.id,
            "label": version_label(f),
            "quality": quality_label(f),
            **_track_fields(f),
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
        for f in features
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
    # Clearlogo for the big picture movie page (manual override wins).
    data.update(await _logo_fields(movie))
    data["in_watchlist"] = bool(await session.scalar(
        select(WatchlistItem.id).where(WatchlistItem.movie_id == movie.id)))
    # "More in this series": the franchise's other movies in the library.
    data["series"] = None
    if movie.collection_id:
        sibs = (await session.scalars(
            select(Movie).options(selectinload(Movie.files))
            .where(Movie.collection_id == movie.collection_id)
        )).all()
        if len(sibs) > 1:
            data["series"] = {
                "id": movie.collection_id,
                "name": franchise_name(movie.collection_name),
                "movies": [_summary(m) for m in sorted(
                    sibs, key=lambda m: (m.year or 9999, m.title))],
            }
    return data


@router.get("/movies/{movie_id}/trailer")
async def movie_trailer(
    movie_id: int, variant: str = "sdr", session: AsyncSession = Depends(get_session)
) -> FileResponse:
    """Serve the cached trailer, fetching it on first request. SDR by default —
    every client can show it; `?variant=hdr` gets the HDR master when there is
    one (Roku / the native player). 404 if the movie has no usable trailer."""
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    path = await ensure_trailer(
        movie_id, movie.tmdb_id, movie.trailer_youtube, movie.title, movie.year
    )
    if not path:
        raise HTTPException(status_code=404, detail="No trailer available")
    return FileResponse(
        serve_file(movie_id, hdr=variant == "hdr"),
        media_type="video/x-matroska",
        headers={"Cache-Control": "no-cache"},
    )


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


class MovieUpdate(BaseModel):
    bluray_url: str | None = None
    logo_url: str | None = None
    trailer_youtube: str | None = None


@router.patch("/movies/{movie_id}")
async def update_movie(
    movie_id: int,
    body: MovieUpdate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    movie = await session.scalar(select(Movie).where(Movie.id == movie_id))
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    if body.bluray_url is not None:
        movie.bluray_url = body.bluray_url.strip() or None
    if body.logo_url is not None:
        movie.logo_url = body.logo_url.strip() or None
    if body.trailer_youtube is not None:
        movie.trailer_youtube = body.trailer_youtube.strip() or None
        clear_trailer(movie.id)  # drop the old cached file so the new pin re-pulls
    await session.commit()
    return {
        "id": movie.id,
        "bluray_url": movie.bluray_url,
        "logo_url": movie.logo_url,
        "trailer_youtube": movie.trailer_youtube,
    }


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
async def trigger_scan(wait: bool = True) -> dict:
    """Scan the library. Default waits and returns the counts (the app's
    Library button); ?wait=false starts it in the background and returns at
    once (the placement script) — follow it on GET /api/scan/status."""
    if not wait:
        return start_background_scan()
    return await scan()


@router.get("/scan/status")
async def get_scan_status() -> dict:
    return scan_state()


@router.post("/trailers/fill")
async def trailers_fill(verify: bool = False, session: AsyncSession = Depends(get_session)) -> dict:
    """Background: fetch a trailer for every movie that lacks one; ?verify=true
    also re-checks cached trailers and re-pulls broken ones. Follow it on
    GET /api/trailers/fill."""
    movies = (await session.scalars(select(Movie).order_by(Movie.id))).all()
    todo = [(m.id, m.tmdb_id, m.trailer_youtube, m.title, m.year) for m in movies
            if m.tmdb_id or m.trailer_youtube]
    return start_fill(todo, verify=verify)


@router.get("/trailers/fill")
async def trailers_fill_status() -> dict:
    return fill_state()


@router.post("/backfill-certifications")
async def trigger_backfill_certifications(limit: int | None = None) -> dict:
    """Fetch content ratings (PG-13, R …) for movies that don't have one yet."""
    return await backfill_certifications(limit)


@router.post("/backfill-universes")
async def trigger_backfill_universes(limit: int | None = None) -> dict:
    """Tag existing movies for the curated tiles (MCU / Disney Animation /
    Pixar) + full release dates. Safe to re-run — only untagged movies."""
    return await backfill_universes(limit)


@router.post("/backfill-ratings")
async def trigger_backfill(limit: int | None = None) -> dict:
    """Populate popularity / external ratings / collection on existing movies.
    Safe to re-run — only touches movies that don't have the data yet."""
    return await backfill_ratings(limit)


@router.post("/reprobe")
async def trigger_reprobe(limit: int | None = None, all: bool = False) -> dict:
    """Fill media_streams (+ edition labels) for files already in the library.
    Default = only files with no stream rows; ?all=true re-probes everything."""
    return await reprobe(limit, only_missing=not all)


# --- Apple TV trailer upgrade (library-wide, background) ----------------------

_upgrade: dict = {"running": False}


async def _run_upgrade(replace_pins: bool, limit: int | None) -> None:
    st = _upgrade
    try:
        async with SessionLocal() as session:
            movies = (await session.scalars(select(Movie).order_by(Movie.id))).all()
        todo = [m for m in movies if m.tmdb_id and (replace_pins or not m.trailer_youtube)]
        if limit:
            todo = todo[:limit]
        st.update(total=len(todo), done=0, apple=0, already=0, none=0, current=None)
        # One batched Wikidata lookup for the whole library up front.
        await apple_trailers.resolve_ids([m.tmdb_id for m in todo])
        for m in todo:
            st["current"] = m.title
            result = await upgrade_to_apple(m.id, m.tmdb_id)
            st[result] = st.get(result, 0) + 1
            if result == "apple" and m.trailer_youtube:
                # Apple replaced a YouTube pin — drop the pin so it stays Apple.
                async with SessionLocal() as session:
                    row = await session.get(Movie, m.id)
                    if row:
                        row.trailer_youtube = None
                        await session.commit()
                st.setdefault("unpinned", []).append({"id": m.id, "title": m.title,
                                                      "was": m.trailer_youtube})
            st["done"] += 1
    except Exception as e:  # report, don't die silently
        st["error"] = repr(e)
    finally:
        st["running"] = False
        st["current"] = None


@router.post("/trailers/apple-upgrade")
async def start_apple_upgrade(replace_pins: bool = False, limit: int | None = None) -> dict:
    """Swap every movie's trailer for Apple TV's where Apple has one (keeps the
    current trailer otherwise). replace_pins also upgrades manually pinned
    movies and clears their pin. Runs in the background — poll GET."""
    if _upgrade.get("running"):
        return _upgrade
    _upgrade.clear()
    _upgrade.update(running=True, replace_pins=replace_pins)
    asyncio.create_task(_run_upgrade(replace_pins, limit))
    return _upgrade


@router.get("/trailers/apple-upgrade")
async def apple_upgrade_status() -> dict:
    return _upgrade


@router.get("/movies/{movie_id}/trailer/source")
async def movie_trailer_source(movie_id: int) -> dict:
    """Where the cached trailer came from (Apple/YouTube, variants, audio)."""
    return trailer_source(movie_id) or {}


# --- Franchises (TMDB collections) --------------------------------------------

_MIN_FRANCHISE = 2  # a "franchise" needs at least this many movies here


def _release_order(ms: list[Movie]) -> list[Movie]:
    """True release order (full dates when known, else the year)."""
    return sorted(ms, key=lambda m: (m.release_date or f"{m.year or 9999}-12-31", m.title))


def _backdrop_url(m: Movie) -> str | None:
    p = m.backdrop_path
    if not p:
        return None
    return p if p.startswith("http") else f"https://image.tmdb.org/t/p/original{p}"


async def _curated(movies: list[Movie], summ: dict[int, dict]) -> list[dict]:
    """MCU / Disney Animation / Pixar — tiles TMDB has no collection for
    (metadata.CURATED), in release order, ahead of the TMDB franchises."""
    out = []
    for cid, (key, name, company) in CURATED.items():
        ms = _release_order([m for m in movies if key in (m.universes or [])])
        if len(ms) < _MIN_FRANCHISE:
            continue
        years = [m.year for m in ms if m.year]
        top = max(ms, key=lambda m: m.popularity or 0)
        out.append({
            "id": cid,
            "name": name,
            "count": len(ms),
            "years": (f"{min(years)}–{max(years)}" if years and min(years) != max(years)
                      else (str(years[0]) if years else None)),
            "logo": await get_company_logo(company),
            "backdrop": _backdrop_url(top),
            "poster": None,
            "overview": None,
            "backdrops": [summ[m.id]["backdrop_path"] for m in ms
                          if summ.get(m.id, {}).get("backdrop_path")][:10],
            "popularity": sum(m.popularity or 0 for m in ms),
        })
    return out


async def _collections(movies: list[Movie], summ: dict[int, dict],
                       curated: bool = False) -> list[dict]:
    """Every franchise with 2+ movies in the library, biggest/most popular
    first, with its art: TMDB's franchise logo/backdrop plus each member's
    backdrop (the tile's slideshow)."""
    groups: dict[int, list[Movie]] = {}
    for m in movies:
        if m.collection_id:
            groups.setdefault(m.collection_id, []).append(m)
    groups = {k: v for k, v in groups.items() if len(v) >= _MIN_FRANCHISE}
    sem = asyncio.Semaphore(6)

    async def art(cid: int) -> dict | None:
        async with sem:
            return await get_collection_art(cid)

    arts = await asyncio.gather(*(art(cid) for cid in groups))
    # Franchise logos take a few TMDB calls each the first time: never make
    # the home screen wait — fill them in the background, show them next load.
    for cid, a in zip(groups, arts):
        if cid not in _franchise_logo_cache() and cid not in _logo_pending:
            _logo_pending.add(cid)
            name = franchise_name((a or {}).get("name") or groups[cid][0].collection_name)
            asyncio.create_task(_fill_franchise_logo(cid, name))
    out = []
    for (cid, ms), a in zip(groups.items(), arts):
        ms = sorted(ms, key=lambda m: (m.year or 9999, m.title))
        years = [m.year for m in ms if m.year]
        out.append({
            "id": cid,
            "name": franchise_name((a or {}).get("name") or ms[0].collection_name),
            "count": len(ms),
            "years": (f"{min(years)}–{max(years)}" if years and min(years) != max(years)
                      else (str(years[0]) if years else None)),
            "logo": _franchise_logo_cache().get(cid),
            "backdrop": (a or {}).get("backdrop"),
            "poster": (a or {}).get("poster"),
            "overview": (a or {}).get("overview"),
            "backdrops": [summ[m.id]["backdrop_path"] for m in ms
                          if summ.get(m.id, {}).get("backdrop_path")][:10],
            "popularity": sum(m.popularity or 0 for m in ms),
        })
    out.sort(key=lambda c: (c["popularity"], c["count"]), reverse=True)
    # Curated tiles only on the row/list — the single-franchise page reuses
    # this for ONE TMDB collection and must not get an "MCU" entry back.
    return (await _curated(movies, summ) + out) if curated else out


_logo_pending: set[int] = set()


def _franchise_logo_cache() -> dict[int, str | None]:
    from ..metadata import _franchise_logo
    return _franchise_logo


async def _fill_franchise_logo(cid: int, name: str) -> None:
    try:
        await get_franchise_logo(cid, name)
    finally:
        _logo_pending.discard(cid)


@router.get("/collections")
async def list_collections(session: AsyncSession = Depends(get_session)) -> list[dict]:
    movies = (await session.scalars(select(Movie).options(selectinload(Movie.files)))).all()
    return await _collections(movies, {m.id: _summary(m) for m in movies}, curated=True)


@router.get("/collections/{collection_id}")
async def get_collection(
    collection_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    """A franchise page: its art + its movies in release order."""
    if collection_id < 0:  # curated (MCU / Disney Animation / Pixar)
        cur = CURATED.get(collection_id)
        if not cur:
            raise HTTPException(status_code=404, detail="Collection not found")
        key, name, company = cur
        allm = (await session.scalars(select(Movie).options(selectinload(Movie.files)))).all()
        ms = _release_order([m for m in allm if key in (m.universes or [])])
        if not ms:
            raise HTTPException(status_code=404, detail="Collection not found")
        summ = {m.id: _summary(m) for m in ms}
        years = [m.year for m in ms if m.year]
        return {
            "id": collection_id,
            "name": name,
            "count": len(ms),
            "years": (f"{min(years)}–{max(years)}" if years and min(years) != max(years)
                      else (str(years[0]) if years else None)),
            "logo": await get_company_logo(company),
            "backdrop": _backdrop_url(max(ms, key=lambda m: m.popularity or 0)),
            "overview": None,
            "movies": [summ[m.id] for m in ms],
        }
    ms = (await session.scalars(
        select(Movie).options(selectinload(Movie.files))
        .where(Movie.collection_id == collection_id)
    )).all()
    if not ms:
        raise HTTPException(status_code=404, detail="Collection not found")
    summ = {m.id: _summary(m) for m in ms}
    info = (await _collections(ms, summ) or [{}])[0] if len(ms) >= _MIN_FRANCHISE else {}
    a = await get_collection_art(collection_id) or {}
    ordered = sorted(ms, key=lambda m: (m.year or 9999, m.title))
    name = info.get("name") or franchise_name(a.get("name") or ms[0].collection_name)
    return {
        "id": collection_id,
        "name": name,
        "count": len(ms),
        "years": info.get("years"),
        # The franchise page can wait a moment for its logo.
        "logo": await get_franchise_logo(collection_id, name),
        "backdrop": a.get("backdrop"),
        "overview": a.get("overview"),
        "movies": [summ[m.id] for m in ordered],
    }


@router.get("/movies/{movie_id}/related")
async def movie_related(
    movie_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    """Cast + "More like this" — only movies in the library: TMDB's
    recommended/similar titles first, topped up with same-genre movies;
    never this movie or its own franchise (the series row covers those)."""
    movie = await session.get(Movie, movie_id)
    if not movie:
        raise HTTPException(status_code=404, detail="Movie not found")
    rel = (await get_related(movie.tmdb_id)) if movie.tmdb_id else None
    library = (await session.scalars(select(Movie).options(selectinload(Movie.files)))).all()

    def eligible(m: Movie) -> bool:
        return m.id != movie.id and not (
            movie.collection_id and m.collection_id == movie.collection_id)

    by_tmdb = {m.tmdb_id: m for m in library if m.tmdb_id and eligible(m)}
    picks: list[Movie] = [by_tmdb[t] for t in (rel or {}).get("related", []) if t in by_tmdb]
    if len(picks) < 12 and movie.genres:
        mine = set(movie.genres)
        chosen = {m.id for m in picks}
        extra = sorted(
            (m for m in library if eligible(m) and m.id not in chosen
             and len(mine & set(m.genres or [])) >= min(2, len(mine))),
            key=lambda m: (len(mine & set(m.genres or [])), m.popularity or 0),
            reverse=True,
        )
        picks += extra[: 12 - len(picks)]
    return {
        "cast": (rel or {}).get("cast", []),
        "more_like_this": [_summary(m) for m in picks[:12]],
    }


# --- My List -------------------------------------------------------------------

@router.get("/watchlist")
async def get_watchlist(session: AsyncSession = Depends(get_session)) -> list[dict]:
    rows = (await session.scalars(
        select(WatchlistItem).order_by(WatchlistItem.added_at.desc()))).all()
    if not rows:
        return []
    ms = {m.id: m for m in (await session.scalars(
        select(Movie).options(selectinload(Movie.files))
        .where(Movie.id.in_([r.movie_id for r in rows])))).all()}
    return [_summary(ms[r.movie_id]) for r in rows if r.movie_id in ms]


@router.put("/watchlist/{movie_id}")
async def add_to_watchlist(movie_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    if not await session.get(Movie, movie_id):
        raise HTTPException(status_code=404, detail="Movie not found")
    if not await session.scalar(
            select(WatchlistItem.id).where(WatchlistItem.movie_id == movie_id)):
        session.add(WatchlistItem(movie_id=movie_id))
        await session.commit()
    return {"in_watchlist": True}


@router.delete("/watchlist/{movie_id}")
async def remove_from_watchlist(movie_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    """Take a movie off My List (the user's own toggle)."""
    for row in (await session.scalars(
            select(WatchlistItem).where(WatchlistItem.movie_id == movie_id))).all():
        await session.delete(row)
    await session.commit()
    return {"in_watchlist": False}
