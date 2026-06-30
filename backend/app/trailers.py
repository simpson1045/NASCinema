"""Movie trailer caching.

TMDB only gives us YouTube trailer links, and Roku can't stream YouTube
directly — so we download the trailer once with yt-dlp, cache it as a plain MP4,
and serve that file. The featured hero on the TV then plays a real video.

Lazy + idempotent: the file for a movie only appears once the download fully
completes (yt-dlp writes to a .part first), so "<id>.mp4 exists" == ready. A
per-movie lock keeps two concurrent requests from downloading the same trailer.
"""

from __future__ import annotations

import asyncio
import subprocess
from pathlib import Path

from .config import get_settings
from .ffmpeg import ffmpeg_path, yt_dlp_path
from .metadata import get_movie_videos

# movie_id -> lock, so concurrent callers coalesce onto one download.
_locks: dict[int, asyncio.Lock] = {}
# tmdb_id -> best trailer YouTube key (or None). Cached per process.
_key_cache: dict[int, str | None] = {}


def trailers_dir() -> Path:
    s = get_settings()
    d = Path(s.trailers_dir) if s.trailers_dir.strip() else (s.data_dir / "trailers")
    d.mkdir(parents=True, exist_ok=True)
    return d


def trailer_file(movie_id: int) -> Path:
    # MKV so VP9 (4K/1440p) and H.264 (1080p) both fit one container the Roku
    # already plays for movies.
    return trailers_dir() / f"{movie_id}.mkv"


def is_cached(movie_id: int) -> bool:
    f = trailer_file(movie_id)
    return f.exists() and f.stat().st_size > 0


def trailer_version(movie_id: int) -> int:
    """Cache-buster: the cached file's mtime (0 if not cached). Appended to the
    trailer URL so the TV refetches when the file is re-downloaded."""
    f = trailer_file(movie_id)
    return int(f.stat().st_mtime) if f.exists() else 0


async def _best_trailer_key(tmdb_id: int) -> str | None:
    if tmdb_id in _key_cache:
        return _key_cache[tmdb_id]
    videos = await get_movie_videos(tmdb_id)
    key: str | None = None
    if videos:
        # Prefer an actual Trailer, US-region, official upload, then the highest
        # TMDB-reported size — that's the sharp American trailer, not a random old
        # low-res fan upload.
        def _score(v: dict) -> tuple:
            return (
                1 if v.get("type") == "Trailer" else 0,
                1 if v.get("region") == "US" else 0,
                1 if v.get("official") else 0,
                v.get("size") or 0,
            )

        key = max(videos, key=_score).get("key")
    _key_cache[tmdb_id] = key
    return key


async def ensure_trailer(movie_id: int, tmdb_id: int | None) -> Path | None:
    """Return the cached trailer file for a movie, downloading it first if
    needed. Returns None if there's no trailer, no yt-dlp, or the fetch fails."""
    if is_cached(movie_id):
        return trailer_file(movie_id)
    if not tmdb_id:
        return None
    ytdlp = yt_dlp_path()
    if not ytdlp:
        return None

    lock = _locks.setdefault(movie_id, asyncio.Lock())
    async with lock:
        if is_cached(movie_id):  # filled while we waited on the lock
            return trailer_file(movie_id)

        key = await _best_trailer_key(tmdb_id)
        if not key:
            return None

        out = trailer_file(movie_id)
        cap = max(480, get_settings().trailer_max_height)
        # Exclude AV1 (the Ultra 4802 can't decode it) and take the HIGHEST-res
        # VP9 up to the cap, preferring AAC (m4a) audio the Roku plays cleanly.
        # -S res sorts highest-first so real 4K VP9 wins over a 1080p variant
        # when a 4K upload exists, cascading down only when it doesn't.
        fmt = (
            f"bv*[height<={cap}][vcodec!*=av01]+ba[ext=m4a]/"
            f"bv*[height<={cap}][vcodec!*=av01]+ba/"
            f"b[height<={cap}][vcodec!*=av01]/b[height<={cap}]"
        )
        # --ignore-config: don't let a global yt-dlp.conf (e.g. NASRadio's) override
        # our format/sort. -o uses %(ext)s; merge/remux force the final .mkv, which
        # appears only on full completion (so is_cached never sees a partial).
        args = [
            ytdlp,
            "--ignore-config",
            "-f", fmt,
            "-S", "res,vcodec:vp9",
            "--no-playlist",
            "--merge-output-format", "mkv",
            "--remux-video", "mkv",
            "-o", str(trailers_dir() / f"{movie_id}.%(ext)s"),
            f"https://www.youtube.com/watch?v={key}",
        ]
        ff = ffmpeg_path()
        if ff:
            args[1:1] = ["--ffmpeg-location", ff]

        # Run yt-dlp in a thread (subprocess.run), NOT asyncio.create_subprocess_exec:
        # the app forces a SelectorEventLoop for psycopg, and on Windows that loop
        # can't spawn async subprocesses (NotImplementedError). Same pattern as
        # probe.py's ffprobe call.
        def _run() -> subprocess.CompletedProcess:
            return subprocess.run(args, capture_output=True, text=True, timeout=600)

        try:
            proc = await asyncio.to_thread(_run)
        except (subprocess.TimeoutExpired, OSError):
            return None

        if proc.returncode != 0 or not is_cached(movie_id):
            # Clean up any partial output so a retry starts fresh.
            if out.exists() and out.stat().st_size == 0:
                out.unlink(missing_ok=True)
            return None
        return out
