"""Library scanner: walk media folders, parse filenames, probe, fetch metadata,
and upsert movies + files. Idempotent — already-known files are skipped, and
movies the user has `locked` are never re-matched."""

from __future__ import annotations

import os
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

# NAS/system folders to never descend into (Synology trash, thumbnail index,
# snapshots, Syncthing). Matched case-insensitively; dot-folders also skipped.
EXCLUDED_DIRS = {
    "#recycle", "@eadir", "#snapshot", "#snapshots", ".stfolder", ".stversions",
    "$recycle.bin", "system volume information", "lost+found",
}

# Bonus-content subfolders (Kodi/Plex/Jellyfin convention). For the movies MVP
# these aren't separate titles — they'll become "Extras" on the detail page in a
# later phase — so skip them and keep featurettes out of the library.
EXTRAS_DIRS = {
    "featurettes", "extras", "behind the scenes", "deleted scenes", "interviews",
    "scenes", "shorts", "trailers", "other", "specials", "sample", "samples",
    "bonus", "making of", "storyboard art",
}


async def scan(limit: int | None = None) -> dict:
    settings = get_settings()
    dirs = settings.media_dir_list

    stats = {
        "folders": len(dirs),
        "found": 0,
        "added": 0,
        "matched": 0,
        "skipped": 0,
        "errors": 0,
    }
    if not dirs:
        return stats

    async with SessionLocal() as session:
        reached_limit = False
        for directory in dirs:
            if reached_limit:
                break
            for root, subdirs, files in os.walk(directory):
                # Prune system/trash folders in place so os.walk won't descend.
                subdirs[:] = [
                    d
                    for d in subdirs
                    if d.lower() not in EXCLUDED_DIRS
                    and d.lower() not in EXTRAS_DIRS
                    and not d.startswith(".")
                ]
                if reached_limit:
                    break
                for name in files:
                    if Path(name).suffix.lower() not in VIDEO_EXTENSIONS:
                        continue
                    stats["found"] += 1
                    full = os.path.join(root, name)

                    existing = await session.scalar(
                        select(MediaFile).where(MediaFile.path == full)
                    )
                    if existing:
                        stats["skipped"] += 1
                        continue

                    try:
                        # Title source: prefer whichever of the parent folder or
                        # the filename carries a year — that's the strong "this is
                        # a real movie name" signal. Handles both "Title (Year)/
                        # file.ext" libraries and scene-named files sitting loose
                        # in a directory (where the folder is just the root).
                        folder = os.path.basename(os.path.dirname(full))
                        finfo = guessit(folder)
                        ninfo = guessit(name)
                        if finfo.get("year") and finfo.get("title"):
                            title, year = finfo["title"], finfo["year"]
                        elif ninfo.get("year") and ninfo.get("title"):
                            title, year = ninfo["title"], ninfo["year"]
                        else:
                            title = finfo.get("title") or ninfo.get("title") or Path(name).stem
                            year = finfo.get("year") or ninfo.get("year")
                        title = str(title)

                        probe = await probe_file(full) or {}
                        meta = await get_movie_metadata(title, year)

                        movie = await _find_or_create_movie(session, title, year, meta)
                        session.add(
                            MediaFile(
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
                        )
                        # Commit per file: live progress + crash resilience, and
                        # one bad file can't abort the whole scan.
                        await session.commit()
                    except Exception:
                        await session.rollback()
                        stats["errors"] += 1
                        continue

                    if meta:
                        stats["matched"] += 1
                    stats["added"] += 1

                    if limit and stats["added"] >= limit:
                        reached_limit = True
                        break

    return stats


async def _find_or_create_movie(session, title, year, meta) -> Movie:
    # Prefer matching an existing movie by TMDB id (handles multi-version files).
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
    await session.flush()  # assign movie.id for the FK
    return movie
