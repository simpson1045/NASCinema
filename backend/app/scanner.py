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
from sqlalchemy import func, select

from .config import get_settings
from .db import SessionLocal
from .fingerprint import fingerprint_file
from .metadata import get_movie_metadata, get_omdb_ratings
from .models import MediaFile, Movie
from .probe import probe_file
from .models.media_stream import MediaStream
from .streaming import remove_file_cache

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
    # The OUTERMOST extras-looking folder decides: everything inside it, at any
    # depth, is an extra of the folder above it ("Movie/Bonus Features/
    # Storyboard Art/x.mkv" belongs to "Movie", not to "Bonus Features").
    for i, d in enumerate(dirs):
        if _is_extras_dir(d):
            if i >= 1:
                return True, dirs[i - 1], d.lower()
            # A top-level bonus disc ("Back to the Future Trilogy Bonus Disc")
            # belongs to the film it names.
            return True, _strip_bonus_words(d), d.lower()
    return False, (dirs[-1] if dirs else None), None


# Folder-name fragments that mark bonus content even when the exact name isn't
# in EXTRAS_DIRS ("Bonus Features", "Special Features", "Production Photos"...).
_EXTRAS_HINTS = ("bonus", "special feature", "featurette", "extras",
                 "production photo", "storyboard", "deleted scene",
                 "behind the scene")
_BONUS_WORDS = re.compile(
    r"\b(trilogy|collection|bonus|disc|features?|special|extras)\b", re.IGNORECASE)


def _is_extras_dir(name: str) -> bool:
    low = name.lower()
    return low in EXTRAS_DIRS or any(h in low for h in _EXTRAS_HINTS)


def _strip_bonus_words(name: str) -> str:
    return " ".join(_BONUS_WORDS.sub(" ", name).split()) or name


_FOLDER_TITLE = re.compile(r"^(.*?)\s*\((\d{4})\)")


def _derive_title(movie_folder: str | None, filename: str) -> tuple[str, int | None]:
    """Resolve the movie title + year.

    A clean ``Title (Year)`` folder is authoritative and keeps sequel markers
    intact (e.g. "Back to the Future Part III") — guessit would strip "Part III"
    into a separate field, collapsing sequels onto the base film. Fall back to
    guessit's year-bearing parse for files sitting loose in a directory.
    """
    if movie_folder:
        m = _FOLDER_TITLE.match(movie_folder)
        if m:
            return m.group(1).strip(), int(m.group(2))

    finfo = guessit(movie_folder) if movie_folder else {}
    ninfo = guessit(filename)
    if finfo.get("year") and finfo.get("title"):
        return str(finfo["title"]), finfo.get("year")
    if ninfo.get("year") and ninfo.get("title"):
        return str(ninfo["title"]), ninfo.get("year")
    # No year anywhere: trust the folder name as written. guessit reads
    # "Jurassic World - Dominion" as title "Jurassic World" + an episode name,
    # which then matched the wrong film.
    if movie_folder:
        clean = " ".join(re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", movie_folder).split())
        if clean:
            return clean, (finfo.get("year") or ninfo.get("year"))
    title = ninfo.get("title") or Path(filename).stem
    return str(title), ninfo.get("year")


# Keyword -> extra type, matched against the filename (more specific than the
# folder, which is often just one catch-all "Featurettes" dir).
_EXTRA_NAME_TYPES = [
    ("teaser", "Trailer"), ("trailer", "Trailer"), ("deleted", "Deleted Scene"),
    ("behind the scenes", "Behind the Scenes"), ("making of", "Behind the Scenes"),
    ("making-of", "Behind the Scenes"), ("interview", "Interview"),
    ("documentary", "Documentary"), ("music video", "Music Video"),
    ("blooper", "Blooper"), ("gag reel", "Blooper"), ("outtake", "Blooper"),
    ("featurette", "Featurette"),
]


# Version labels. `{edition-Name}` is the Plex/Jellyfin convention and wins
# outright; otherwise a known cut/fan-edit keyword anywhere in the filename or
# its folder. Untagged files get None and the API labels them by resolution/HDR.
_EDITION_TAG = re.compile(r"\{edition-([^}]+)\}", re.IGNORECASE)
_EDITION_WORDS: list[tuple[str, str]] = [
    (r"\b4k77\b", "4K77"),
    (r"\b4k80\b", "4K80"),
    (r"\b4k83\b", "4K83"),
    (r"harmy|despecialized", "Harmy Despecialized"),
    (r"director'?s?\s*cut", "Director's Cut"),
    (r"\bextended\b", "Extended"),
    (r"\btheatrical\b", "Theatrical"),
    (r"\bultimate\s*(cut|edition)\b", "Ultimate Cut"),
    (r"\bfinal\s*cut\b", "Final Cut"),
    (r"\bspecial\s*edition\b", "Special Edition"),
    (r"\bunrated\b", "Unrated"),
    (r"\buncut\b", "Uncut"),
    (r"\bremastered\b", "Remastered"),
    (r"\bcriterion\b", "Criterion"),
    (r"\bimax\b", "IMAX"),
    (r"\bopen\s*matte\b", "Open Matte"),
    (r"\bfan\s*edit\b", "Fan Edit"),
]


def _edition(filename: str, movie_folder: str | None) -> str | None:
    for text in (filename, movie_folder or ""):
        m = _EDITION_TAG.search(text)
        if m:
            return m.group(1).strip()
    hay = f"{filename} {movie_folder or ''}"
    for pat, label in _EDITION_WORDS:
        if re.search(pat, hay, flags=re.IGNORECASE):
            return label
    return None


def _stream_rows(probe: dict) -> list[MediaStream]:
    return [MediaStream(**row) for row in probe.get("streams") or []]


def _extra_type(filename: str, folder_key: str | None) -> str:
    low = filename.lower()
    for keyword, label in _EXTRA_NAME_TYPES:
        if keyword in low:
            return label
    return EXTRA_TYPE_LABELS.get(folder_key, "Featurette")


def _extra_title(filename: str, movie_title: str, extra_type: str) -> str:
    """Clean an extra's display name: drop a leading movie-title prefix, a
    redundant type prefix ("Behind the Scenes - "), and any MakeMKV-style `_t07`
    disc-title suffix."""
    stem = Path(filename).stem
    if movie_title and stem.lower().startswith(movie_title.lower()):
        stem = stem[len(movie_title):].lstrip(" -_.")
    stem = re.sub(
        rf"^{re.escape(extra_type)}s?\s*[-:_]\s*", "", stem, flags=re.IGNORECASE
    )
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
        "removed": 0,
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
                        mf.streams = _stream_rows(probe)
                        if is_extra:
                            mf.kind = "extra"
                            mf.extra_type = _extra_type(name, extras_key)
                            mf.extra_title = _extra_title(name, movie.title, mf.extra_type)
                            if settings.contribute_extras:
                                mf.fingerprint = await fingerprint_file(full)
                        else:
                            mf.edition = _edition(name, movie_folder)
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

        # Prune files whose source is gone — but only under roots we can
        # actually reach, so an offline mount never wipes the library.
        accessible = [os.path.normpath(d) for d in dirs if os.path.isdir(d)]
        if accessible:
            for mf in (await session.scalars(select(MediaFile))).all():
                p = os.path.normpath(mf.path)
                if any(p.startswith(r) for r in accessible) and not os.path.exists(
                    mf.path
                ):
                    remove_file_cache(mf.id)  # drop stale cached transcode
                    await session.delete(mf)
                    stats["removed"] += 1
            await session.commit()
            # Drop movies that are left with no files at all.
            for mv in (await session.scalars(select(Movie))).all():
                n = await session.scalar(
                    select(func.count(MediaFile.id)).where(
                        MediaFile.movie_id == mv.id
                    )
                )
                if not n:
                    await session.delete(mv)
            await session.commit()

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
        movie.popularity = meta.get("popularity")
        movie.vote_count = meta.get("vote_count")
        movie.imdb_id = meta.get("imdb_id")
        movie.collection_id = meta.get("collection_id")
        movie.collection_name = meta.get("collection_name")
        omdb = await get_omdb_ratings(meta.get("imdb_id") or "")
        if omdb:
            movie.imdb_rating = omdb.get("imdb_rating")
            movie.rt_score = omdb.get("rt_score")
            movie.metacritic = omdb.get("metacritic")

    session.add(movie)
    await session.flush()
    return movie


async def backfill_ratings(limit: int | None = None) -> dict:
    """Populate the ranking/grouping fields on movies scanned before this
    existed — re-fetch TMDB by tmdb_id (popularity, votes, imdb_id, collection)
    and OMDb by imdb_id (IMDB/RT/Metacritic). Independent of the file scan, so it
    runs on the current library without touching the NAS.
    """
    from .metadata import get_movie_metadata_by_id

    stats = {"updated": 0, "skipped": 0, "failed": 0}
    async with SessionLocal() as session:
        q = select(Movie).where(Movie.tmdb_id.isnot(None), Movie.popularity.is_(None))
        if limit:
            q = q.limit(limit)
        movies = (await session.scalars(q)).all()
        for movie in movies:
            meta = await get_movie_metadata_by_id(movie.tmdb_id)
            if not meta:
                stats["failed"] += 1
                continue
            movie.popularity = meta.get("popularity")
            movie.vote_count = meta.get("vote_count")
            movie.imdb_id = meta.get("imdb_id")
            movie.collection_id = meta.get("collection_id")
            movie.collection_name = meta.get("collection_name")
            omdb = await get_omdb_ratings(meta.get("imdb_id") or "")
            if omdb:
                movie.imdb_rating = omdb.get("imdb_rating")
                movie.rt_score = omdb.get("rt_score")
                movie.metacritic = omdb.get("metacritic")
            stats["updated"] += 1
        await session.commit()
    return stats


async def fingerprint_extras() -> dict:
    """Backfill Chromaprint fingerprints for extras that don't have one yet
    (Extras DB groundwork)."""
    stats = {"fingerprinted": 0, "failed": 0}
    async with SessionLocal() as session:
        rows = (
            await session.scalars(
                select(MediaFile).where(
                    MediaFile.kind == "extra", MediaFile.fingerprint.is_(None)
                )
            )
        ).all()
        for mf in rows:
            fp = await fingerprint_file(mf.path)
            if fp:
                mf.fingerprint = fp
                stats["fingerprinted"] += 1
            else:
                stats["failed"] += 1
            await session.commit()
    return stats


async def reprobe(limit: int | None = None, only_missing: bool = True) -> dict:
    """Re-run ffprobe over files already in the library and (re)write their
    media_streams rows + edition label. The scan skips known paths, so this is
    how the existing library gets per-track data. `only_missing` limits it to
    files with no stream rows yet; False re-probes everything."""
    from sqlalchemy.orm import selectinload

    stats = {"checked": 0, "probed": 0, "missing": 0, "failed": 0}
    async with SessionLocal() as session:
        files = (
            await session.scalars(
                select(MediaFile).options(selectinload(MediaFile.streams)).order_by(MediaFile.id)
            )
        ).all()
        for mf in files:
            if only_missing and mf.streams:
                continue
            stats["checked"] += 1
            if not os.path.exists(mf.path):
                stats["missing"] += 1
                continue
            probe = await probe_file(mf.path)
            if not probe:
                stats["failed"] += 1
                continue
            try:
                mf.streams = _stream_rows(probe)
                for key in ("container", "video_codec", "audio_codec", "width",
                            "height", "duration", "bit_depth", "size_bytes"):
                    if probe.get(key) is not None:
                        setattr(mf, key, probe[key])
                mf.hdr = probe.get("hdr", False)
                mf.probed_at = datetime.now(timezone.utc)
                if mf.kind == "feature" and mf.edition is None:
                    folder = os.path.basename(os.path.dirname(mf.path))
                    mf.edition = _edition(os.path.basename(mf.path), folder)
                await session.commit()
                stats["probed"] += 1
            except Exception:
                await session.rollback()
                stats["failed"] += 1
            if limit and stats["probed"] >= limit:
                break
    return stats
