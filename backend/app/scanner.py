"""Library scanner: walk media folders, parse filenames, probe, fetch metadata,
and upsert movies + files. Idempotent — already-known files are skipped.

Bonus content (Featurettes/Extras/Trailers/… subfolders) is ingested too, but
tagged as an extra and attached to its parent movie rather than treated as a
separate title — so adding bonus material is just "drop it in the folder and
rescan."
"""

from __future__ import annotations

import os
import re
from datetime import datetime, timezone
from pathlib import Path

from guessit import guessit
from sqlalchemy import select

from .config import get_settings
from .db import SessionLocal
from .metadata import get_movie_metadata
from .models import MediaFile, Movie
from .probe import probe_file

VIDEO_EXTENSIONS = {
    ".mkv", ".mp4", ".m4v", ".avi", ".mov", ".wmv", ".ts", ".m2ts", ".webm", ".flv",
}

# NAS/system folders to never descend into.
EXCLUDED_DIRS = {
    "#recycle", "@eadir", "#snapshot", "#snapshots", ".stfolder", ".stversions",
    "$recycle.bin", "system volume information", "lost+found",
}

# Bonus-content subfolders (Kodi/Plex/Jellyfin convention). We DO descend into
# these now, but everything inside is tagged as an extra of the parent movie.
EXTRAS_DIRS = {
    "featurettes", "extras", "behind the scenes", "deleted scenes", "interviews",
    "scenes", "shorts", "trailers", "other", "specials", "sample", "samples",
    "bonus", "making of", "storyboard art",
}

# Folder name -> human-friendly extra type.
EXTRA_TYPE_LABELS = {
    "featurettes": "Featurette", "extras": "Extra",
    "behind the scenes": "Behind the Scenes", "deleted scenes": "Deleted Scene",
    "interviews": "Interview", "scenes": "Scene", "shorts": "Short",
    "trailers": "Trailer", "other": "Extra", "specials": "Special",
    "sample": "Sample", "samples": "Sample", "bonus": "Bonus",
    "making of": "Making Of", "storyboard art": "Storyboard",
}


def _classify(full: str, media_dir: str) -> tuple[bool, str | None, str | None]:
    """Return (is_extra, movie_folder_name, extras_folder_key)."""
    try:
        rel = os.path.relpath(full, media_dir)
    except ValueError:
        rel = full
    dirs = rel.split(os.sep)[:-1]  # drop the filename
    for i, d in enumerate(dirs):
        if d.lower() in EXTRAS_DIRS:
            return True, (dirs[i - 1] if i >= 1 else None), d.lower()
    return False, (dirs[-1] if dirs else None), None


def _derive_title(movie_folder: str | None, filename: str) -> tuple[str, int | None]:
    """Title from whichever of the movie folder / filename carries a year."""
    finfo = guessit(movie_folder) if movie_folder else {}
    ninfo = guessit(filename)
    if finfo.get("year") and finfo.get("title"):
        return str(finfo["title"]), finfo.get("year")
    if ninfo.get("year") and ninfo.get("title"):
        return str(ninfo["title"]), ninfo.get("year")
    title = finfo.get("title") or ninfo.get("title") or Path(filename).stem
    return str(title), (finfo.get("year") or ninfo.get("year"))


def _extra_title(filename: str, movie_title: str) -> str:
    """Clean an extra's display name: drop a leading movie-title prefix and any
    MakeMKV-style `_t07` disc-title suffix."""
    stem = Path(filename).stem
    if movie_title and stem.lower().startswith(movie_title.lower()):
        stem = stem[len(movie_title):].lstrip(" -_.")
    stem = re.sub(r"[ _]t\d{1,3}$", "", stem)
    return stem.strip() or Path(filename).stem


async def scan(limit: int | None = None) -> dict:
    settings = get_settings()
    dirs = settings.media_dir_list

    stats = {
        "folders": len(dirs),
        "found": 0,
        "added": 0,
        "matched": 0,
        "extras": 0,
        "skipped": 0,
        "errors": 0,
    }
    if not dirs:
        return stats

    meta_cache: dict[tuple, dict | None] = {}

    async with SessionLocal() as session:
        reached_limit = False
        for directory in dirs:
            if reached_limit:
                break
            for root, subdirs, files in os.walk(directory):
                # Prune only true system/trash folders; extras are walked.
                subdirs[:] = [
                    d
                    for d in subdirs
                    if d.lower() not in EXCLUDED_DIRS and not d.startswith(".")
                ]
                if reached_limit:
                    break
                for name in files:
                    if Path(name).suffix.lower() not in VIDEO_EXTENSIONS:
                        continue
                    stats["found"] += 1
                    full = os.path.join(root, name)

                    if await session.scalar(
                        select(MediaFile.id).where(MediaFile.path == full)
                    ):
                        stats["skipped"] += 1
                        continue

                    try:
                        is_extra, movie_folder, extras_key = _classify(full, directory)
                        title, year = _derive_title(movie_folder, name)

                        key = (title.lower(), year)
                        if key in meta_cache:
                            meta = meta_cache[key]
                        else:
                            meta = await get_movie_metadata(title, year)
                            meta_cache[key] = meta

                        movie = await _find_or_create_movie(session, title, year, meta)

                        probe = await probe_file(full) or {}
                        mf = MediaFile(
                            movie_id=movie.id,
                            path=full,
                            size_bytes=probe.get("size_bytes"),
                            container=probe.get("container"),
                            video_codec=probe.get("video_codec"),
                            audio_codec=probe.get("audio_codec"),
                            width=probe.get("width"),
                            height=probe.get("height"),
                            duration=probe.get("duration"),
                            bit_depth=probe.get("bit_depth"),
                            hdr=probe.get("hdr", False),
                            probed_at=datetime.now(timezone.utc),
                        )
                        if is_extra:
                            mf.kind = "extra"
                            mf.extra_type = EXTRA_TYPE_LABELS.get(extras_key, "Extra")
                            mf.extra_title = _extra_title(name, movie.title)
                        session.add(mf)
                        await session.commit()
                    except Exception:
                        await session.rollback()
                        stats["errors"] += 1
                        continue

                    if is_extra:
                        stats["extras"] += 1
                    else:
                        if meta:
                            stats["matched"] += 1
                        stats["added"] += 1
                        if limit and stats["added"] >= limit:
                            reached_limit = True
                            break

    return stats


async def _find_or_create_movie(session, title, year, meta) -> Movie:
    if meta and meta.get("tmdb_id"):
        movie = await session.scalar(
            select(Movie).where(Movie.tmdb_id == meta["tmdb_id"])
        )
        if movie:
            return movie

    movie = Movie(
        title=(meta.get("title") if meta else title),
        year=(meta.get("year") if meta else year),
    )
    if meta:
        movie.tmdb_id = meta.get("tmdb_id")
        movie.original_title = meta.get("original_title")
        movie.overview = meta.get("overview")
        movie.runtime = meta.get("runtime")
        movie.rating = meta.get("rating")
        movie.poster_path = meta.get("poster_path")
        movie.backdrop_path = meta.get("backdrop_path")
        movie.genres = meta.get("genres")
        movie.match_confidence = meta.get("match_confidence")

    session.add(movie)
    await session.flush()
    return movie
