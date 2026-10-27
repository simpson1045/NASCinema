"""TV show scanner. Runs after the movie scan, over NASCINEMA_SHOW_DIRS.

Layout (Sonarr's): <root>/<Show (Year)>/Season N/<Show> - SxxEyy - Title.ext.
Each show folder is a show (matched on TMDB once); each file is a MediaFile
(kind='episode') on an Episode row, so streaming / resume / subtitles work as
they do for movies. A replaced file (Sonarr upgrade) keeps the episode and
carries its resume point to the new file.
"""

from __future__ import annotations

import difflib
import os
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import func, select

from .config import get_settings
from .db import SessionLocal
from .metadata import get_season_metadata, get_show_metadata
from .models import Episode, MediaFile, Season, Show
from .probe import probe_file
from .scanner import (
    EXCLUDED_DIRS,
    VIDEO_EXTENSIONS,
    _no_tracks,
    _trackless_ids,
    _carry_over,
    _refresh,
    _rewritten,
    _scan_error,
    _scan_state,
    _stream_rows,
)
from .streaming import remove_file_cache

# S05E17, S2004E04 (MythBusters' year seasons), S01E01E02 / S01E01-E02.
_SXE = re.compile(r"\bS(\d{1,4})[ ._]?E(\d{1,3})(?:-?E(\d{1,3}))?", re.IGNORECASE)
# Looney Tunes Platinum Collection: V01E23 (volume = season).
_VXE = re.compile(r"\bV(\d{1,2})E(\d{1,3})\b", re.IGNORECASE)
_NXN = re.compile(r"\b(\d{1,2})x(\d{2,3})\b")
_SEASON_DIR = re.compile(r"^(?:season|series|volume)\s*(\d{1,4})$", re.IGNORECASE)
# Trailing quality tags Sonarr appends ("Golden Ticket Bluray-1080p") and
# release-group brackets ("(1080p BluRay x265 Garshasp)").
_QUALITY = re.compile(
    r"\s+(?:Bluray|BluRay|WEBDL|WEB-DL|WEBRip|HDTV|SDTV|DVD|DVDRip|Remux|Raw-HD)"
    r"(?:[- ]\w+)*$", re.IGNORECASE)
_BRACKETED = re.compile(
    r"\s*[\[(][^\])]*\b(?:\d{3,4}p|x26[45]|HEVC|BluRay|WEB|DVD|AAC|DTS)\b[^\])]*[\])]\s*$",
    re.IGNORECASE)
_COUNTRY = {"US": "US", "UK": "GB", "AU": "AU", "CA": "CA", "NZ": "NZ"}


def _parse_show_folder(name: str) -> tuple[str, int | None, str | None]:
    """"Avatar - The Last Airbender (2005)" → (title, 2005, None);
    "The Office (US)" → ("The Office", None, "US")."""
    year = country = None
    m = re.search(r"\s*\((\d{4})\)\s*$", name)
    if m:
        year, name = int(m.group(1)), name[: m.start()]
    m = re.search(r"\s*\((US|UK|AU|CA|NZ)\)\s*$", name)
    if m:
        country, name = _COUNTRY[m.group(1)], name[: m.start()]
    return " ".join(name.split()), year, country


# Folders of bonus material inside a show — filed under Specials.
_EXTRAS_DIRS = {"specials", "featurettes", "extras", "behind the scenes",
                "deleted scenes", "interviews", "shorts", "bonus"}


def _clean_title(text: str) -> str | None:
    t = text.strip(" -._")
    for _ in range(2):
        t = _BRACKETED.sub("", t)
        t = _QUALITY.sub("", t).strip(" -._")
    # Dotted scene-release leftovers ("1080p.NF.WEB-DL.DDP5.1.x264-BTN") are
    # not a title — TMDB's episode name fills in.
    if re.match(r"^\d{3,4}p\b", t, re.IGNORECASE) or (" " not in t and t.count(".") >= 2):
        return None
    return t or None


def _parse_episode(path: str, show_dir: str) -> tuple[int, int | None, int | None, str | None]:
    """(season, episode, episode_end, title-from-filename)."""
    stem = Path(path).stem
    rel_parts = [p.lower() for p in Path(os.path.relpath(os.path.dirname(path), show_dir)).parts]
    if any(p in _EXTRAS_DIRS for p in rel_parts):
        # Specials / bonus folders: everything is a special. A numbered file
        # here can be another show's episode (Batman Beyond's Specials hold
        # "Static Shock - S04 E01"), so its own numbers don't count.
        m = _SXE.search(stem)
        if m and int(m.group(1)) == 0:
            return 0, int(m.group(2)), None, _clean_title(stem[m.end():])
        return 0, None, None, _clean_title(stem)
    for rx in (_SXE, _VXE, _NXN):
        m = rx.search(stem)
        if m:
            season, ep = int(m.group(1)), int(m.group(2))
            end = int(m.group(3)) if rx is _SXE and m.group(3) else None
            return season, ep, end, _clean_title(stem[m.end():])
    # No number in the name: season from the folder, episode unknown.
    season = 1
    rel = os.path.relpath(os.path.dirname(path), show_dir)
    for part in Path(rel).parts:
        if part.lower() == "specials":
            season = 0
        m = _SEASON_DIR.match(part)
        if m:
            season = int(m.group(1))
    return season, None, None, _clean_title(stem)


async def _match_show(folder_name: str, year_hint: int | None = None
                      ) -> tuple[dict | None, str, int | None]:
    """`year_hint`: the first year-numbered season (MythBusters' "Season
    2003", Tom and Jerry's "Season 1940") when the folder has no year."""
    title, year, country = _parse_show_folder(folder_name)
    tries: list[tuple[str, int | None]] = [(title, year or year_hint)]
    if " - " in title:
        tries += [(title.replace(" - ", ": "), year), (title.replace(" - ", " "), year)]
    if year or year_hint:
        tries += [(t, None) for t, _ in list(tries)]
    seen = set()
    for t, y in tries:
        if (t, y) in seen:
            continue
        seen.add((t, y))
        meta = await get_show_metadata(t, y, country)
        if meta:
            return meta, title, year
    return None, title, year


def _video_files(show_dir: str) -> list[str]:
    out = []
    for root, subdirs, files in os.walk(show_dir):
        subdirs[:] = [d for d in subdirs
                      if d.lower() not in EXCLUDED_DIRS and not d.startswith(".")]
        out += [os.path.join(root, f) for f in files
                if Path(f).suffix.lower() in VIDEO_EXTENSIONS]
    return sorted(out)


def _tmdb_season(show: Show, season: int) -> tuple[int | None, int]:
    """Where a folder season's details live on TMDB: (tmdb_id, tmdb season).
    season_map routes merged folders (Whose Line 9+ → the 2013 revival, −8)."""
    for first, tmdb_id, offset in sorted(show.season_map or [], reverse=True):
        if season >= first:
            return tmdb_id, season + offset
    return show.tmdb_id, season


async def _season_meta(cache: dict, show: Show, season: int) -> dict | None:
    tmdb_id, tmdb_season = _tmdb_season(show, season)
    if not tmdb_id or season == 0 and show.season_map:
        return None
    if season >= _YEAR_SEASON and tmdb_season == season:
        return await _year_season_meta(cache, tmdb_id, season)
    key = (tmdb_id, tmdb_season)
    if key not in cache:
        cache[key] = await get_season_metadata(tmdb_id, tmdb_season)
    return cache[key]


_YEAR_SEASON = 1900  # "Season 2003": a folder numbered by year, not TMDB's season


def _title_key(title: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())


async def _all_tmdb_seasons(cache: dict, tmdb_id: int) -> list[tuple[int, dict]]:
    """Every TMDB season of a show, regular seasons first, Specials last."""
    key = (tmdb_id, "all")
    if key not in cache:
        from .metadata import get_show_metadata_by_id
        meta = await get_show_metadata_by_id(tmdb_id) or {}
        out = []
        for n in sorted(meta.get("seasons") or [], key=lambda n: (n == 0, n)):
            if (tmdb_id, n) not in cache:
                cache[(tmdb_id, n)] = await get_season_metadata(tmdb_id, n)
            if cache[(tmdb_id, n)]:
                out.append((n, cache[(tmdb_id, n)]))
        cache[key] = out
    return cache[key]


async def _year_season_meta(cache: dict, tmdb_id: int, year: int) -> dict | None:
    """Year-numbered folders (MythBusters "Season 2003", Tom and Jerry "Season
    1940"): TMDB numbers its seasons 1, 2, 3… (MythBusters 2003 = TMDB season
    1), and episode numbers inside a year needn't agree with Sonarr's either —
    so episodes are found by TITLE across every TMDB season ("by_title", see
    _episode_meta). The season's poster/overview come from the TMDB season
    that aired that year. Asking TMDB for "season 2003" 404'd: no stills, no
    synopses, filename titles only (2026-10-26)."""
    key = (tmdb_id, "year", year)
    if key not in cache:
        seasons = await _all_tmdb_seasons(cache, tmdb_id)
        by_title: dict[str, dict] = {}
        for _, sm in seasons:
            for em in sm.get("episodes", {}).values():
                if k := _title_key(em.get("title")):
                    by_title.setdefault(k, em)
        aired = [sm for n, sm in seasons if n > 0 and (sm.get("air_date") or "")[:4] == str(year)]
        first = aired[0] if aired else {}
        cache[key] = {
            "name": f"Season {year}",
            "overview": first.get("overview"),
            "poster_path": first.get("poster_path"),
            "air_date": first.get("air_date"),
            "episodes": {},
            "by_title": by_title,
        } if seasons else None
    return cache[key]


def _episode_meta(sm: dict | None, ep: int | None, file_title: str | None) -> dict | None:
    """TMDB's data for one episode: by its number — or, for a year season, by
    the filename's title (exact once punctuation is gone, else a close
    match; no match = keep the filename title rather than guess a still)."""
    if not sm:
        return None
    by_title = sm.get("by_title")
    if by_title is None:
        return (sm.get("episodes") or {}).get(ep) if ep is not None else None
    k = _title_key(file_title)
    if not k:
        return None
    if k in by_title:
        return by_title[k]
    close = difflib.get_close_matches(k, list(by_title), n=1, cutoff=0.85)
    return by_title[close[0]] if close else None


async def _episode_for(session, show: Show, season: int, ep: int | None,
                       ep_end: int | None, file_title: str | None,
                       cache: dict) -> Episode:
    sm = await _season_meta(cache, show, season)
    if not await session.scalar(select(Season.id).where(
            Season.show_id == show.id, Season.season_number == season)):
        session.add(Season(
            show_id=show.id, season_number=season,
            name=(sm or {}).get("name") or ("Specials" if season == 0 else f"Season {season}"),
            overview=(sm or {}).get("overview"), poster_path=(sm or {}).get("poster_path"),
            air_date=(sm or {}).get("air_date")))
        await session.flush()
    if ep is not None:
        existing = await session.scalar(select(Episode).where(
            Episode.show_id == show.id, Episode.season_number == season,
            Episode.episode_number == ep))
        if existing:
            return existing
    em = _episode_meta(sm, ep, file_title)
    episode = Episode(
        show_id=show.id, season_number=season, episode_number=ep, episode_end=ep_end,
        # TMDB's title when it knows the episode; the filename's otherwise
        # (loose shorts, a year-season title TMDB doesn't have).
        title=(em or {}).get("title") or file_title,
        overview=(em or {}).get("overview"), still_path=(em or {}).get("still_path"),
        air_date=(em or {}).get("air_date"), runtime=(em or {}).get("runtime"),
        tmdb_rating=(em or {}).get("rating"))
    session.add(episode)
    await session.flush()
    return episode


def _apply_show_meta(show: Show, meta: dict) -> None:
    show.tmdb_id = meta.get("tmdb_id")
    show.title = meta.get("title") or show.title
    show.year = meta.get("year") or show.year
    show.overview = meta.get("overview")
    show.poster_path = meta.get("poster_path")
    show.backdrop_path = meta.get("backdrop_path")
    show.genres = meta.get("genres") or []
    show.rating = meta.get("rating")
    show.certification = meta.get("certification") or None
    show.status = meta.get("status")
    show.first_air_date = meta.get("first_air_date")


async def rematch_show(show_id: int, tmdb_id: int, season_map: list | None) -> dict:
    """Point a show at a TMDB entry (+ optional season map) and refresh the
    show, its season names and every episode's title/description/still."""
    from .metadata import get_show_metadata_by_id
    meta = await get_show_metadata_by_id(tmdb_id)
    if not meta:
        return {"ok": False, "error": f"TMDB has no show {tmdb_id}"}
    cache: dict = {}
    async with SessionLocal() as session:
        show = await session.get(Show, show_id)
        if not show:
            return {"ok": False, "error": "no such show"}
        _apply_show_meta(show, meta)
        show.season_map = season_map
        updated = 0
        for season in (await session.scalars(select(Season).where(Season.show_id == show_id))).all():
            sm = await _season_meta(cache, show, season.season_number)
            if sm:
                season.name = (f"Season {season.season_number}" if show.season_map
                               else sm.get("name")) or season.name
                season.overview, season.poster_path, season.air_date = (
                    sm.get("overview"), sm.get("poster_path"), sm.get("air_date"))
        for e in (await session.scalars(select(Episode).where(Episode.show_id == show_id))).all():
            if e.episode_number is None:
                continue
            em = _episode_meta(await _season_meta(cache, show, e.season_number),
                               e.episode_number, e.title)
            if em:
                e.title = em.get("title") or e.title
                e.overview, e.still_path = em.get("overview"), em.get("still_path")
                e.air_date, e.runtime, e.tmdb_rating = (
                    em.get("air_date"), em.get("runtime"), em.get("rating"))
                updated += 1
        await session.commit()
        return {"ok": True, "show": show.title, "episodes_updated": updated}


async def scan_shows(stats: dict) -> None:
    """Add new episodes, refresh rewritten files, prune vanished ones."""
    roots = [r for r in get_settings().show_dir_list if os.path.isdir(r)]
    for k in ("shows_added", "episodes_found", "episodes_added",
              "episodes_refreshed", "episodes_removed"):
        stats.setdefault(k, 0)
    if not roots:
        return
    cache: dict = {}
    added: dict[int, list[int]] = defaultdict(list)  # episode id -> new file ids

    async with SessionLocal() as session:
        trackless = await _trackless_ids(session)
        for root in roots:
            for name in sorted(os.listdir(root)):
                show_dir = os.path.join(root, name)
                if (not os.path.isdir(show_dir) or name.startswith(".")
                        or name.lower() in EXCLUDED_DIRS):
                    continue
                files = _video_files(show_dir)
                if not files:
                    continue
                show = await session.scalar(select(Show).where(Show.folder == show_dir))
                if show is None:
                    years = [int(m.group(1)) for d in os.listdir(show_dir)
                             if (m := _SEASON_DIR.match(d)) and int(m.group(1)) >= 1900]
                    meta, title, year = await _match_show(name, min(years) if years else None)
                    show = Show(folder=show_dir, title=title, year=year)
                    if meta:
                        _apply_show_meta(show, meta)
                    session.add(show)
                    await session.commit()
                    stats["shows_added"] += 1

                for path in files:
                    stats["episodes_found"] += 1
                    _scan_state["current"] = path
                    known = (await session.execute(
                        select(MediaFile.id, MediaFile.size_bytes, MediaFile.probed_at)
                        .where(MediaFile.path == path))).first()
                    if known:
                        if known.id in trackless or _rewritten(path, known.size_bytes, known.probed_at):
                            if await _refresh(session, known.id):
                                stats["episodes_refreshed"] += 1
                            else:
                                _no_tracks(stats, path)
                        continue
                    try:
                        season, ep, ep_end, ftitle = _parse_episode(path, show_dir)
                        episode = await _episode_for(session, show, season, ep, ep_end,
                                                     ftitle, cache)
                        probe = await probe_file(path) or {}
                        if not probe.get("streams"):
                            _no_tracks(stats, path)  # saved anyway; retried next scan
                        mf = MediaFile(
                            episode_id=episode.id, kind="episode", path=path,
                            size_bytes=probe.get("size_bytes"),
                            container=probe.get("container"),
                            video_codec=probe.get("video_codec"),
                            audio_codec=probe.get("audio_codec"),
                            width=probe.get("width"), height=probe.get("height"),
                            duration=probe.get("duration"),
                            bit_depth=probe.get("bit_depth"),
                            hdr=probe.get("hdr", False),
                            probed_at=datetime.now(timezone.utc))
                        mf.streams = _stream_rows(probe)
                        session.add(mf)
                        await session.commit()
                        added[episode.id].append(mf.id)
                        stats["episodes_added"] += 1
                    except Exception as e:
                        await session.rollback()
                        _scan_error(stats, path, repr(e))

        # Prune episode files that vanished — only under roots we can reach,
        # so an offline share never wipes the library. A file Sonarr replaced
        # hands its resume point + subtitles to the episode's new file.
        roots_n = [os.path.normpath(r) for r in roots]
        gone = (await session.scalars(select(MediaFile).where(MediaFile.kind == "episode"))).all()
        for mf in gone:
            p = os.path.normpath(mf.path)
            if not any(p.startswith(r) for r in roots_n) or os.path.exists(mf.path):
                continue
            successors = added.get(mf.episode_id or -1)
            if successors:
                await _carry_over(session, mf, successors[0])
            remove_file_cache(mf.id)
            await session.delete(mf)
            stats["episodes_removed"] += 1
        await session.commit()
        # Then episodes with no files, seasons with no episodes, empty shows.
        for e in (await session.scalars(select(Episode))).all():
            if not await session.scalar(select(func.count(MediaFile.id))
                                        .where(MediaFile.episode_id == e.id)):
                await session.delete(e)
        await session.commit()
        for s in (await session.scalars(select(Season))).all():
            if not await session.scalar(select(func.count(Episode.id)).where(
                    Episode.show_id == s.show_id, Episode.season_number == s.season_number)):
                await session.delete(s)
        for sh in (await session.scalars(select(Show))).all():
            if any(os.path.normpath(sh.folder).startswith(r) for r in roots_n) and \
                    not await session.scalar(select(func.count(Episode.id))
                                             .where(Episode.show_id == sh.id)):
                await session.delete(sh)
        await session.commit()
