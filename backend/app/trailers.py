"""Movie trailer caching.

TMDB only gives YouTube links, and Roku can't stream YouTube directly — so we
download a trailer once with yt-dlp, cache it as MKV, and serve that file. The
featured hero plays it.

Quality matters and YouTube uploads vary wildly, so we don't trust a single pick:
we try a movie's trailers in preference order and, for each, probe the actual
result — rejecting low-bitrate mush (a "1080p" file that's really garbage) and
moving to the next candidate. Audio is forced to AAC so the Roku always has sound
(many YouTube tracks are Opus, which the Ultra 4802 won't decode).

Lazy + idempotent: the final <id>.mkv only appears once a download fully completes
+ passes checks. A per-movie lock coalesces concurrent callers.
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
from pathlib import Path

from .config import get_settings
from .ffmpeg import ffmpeg_path, ffprobe_path, yt_dlp_path

# Run the heavy yt-dlp/ffmpeg children below-normal so they never starve the
# event loop (the box also runs Postgres + other apps). Windows-only flag; 0 is a
# harmless no-op elsewhere.
_LOWPRI = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
from .metadata import get_movie_videos

# movie_id -> lock, so concurrent callers coalesce onto one download.
_locks: dict[int, asyncio.Lock] = {}
# tmdb_id -> ranked list of candidate YouTube keys. Cached per process.
_key_cache: dict[int, list] = {}
# Global cap on concurrent trailer work: yt-dlp + ffmpeg are heavy (esp. 4K), and
# even 2 at once pegs the CPU and stalls the API. One at a time, low priority.
_download_sem = asyncio.Semaphore(1)

_MAX_CANDIDATES = 3  # try at most this many trailers before giving up


def _audio_ok(info: dict) -> bool:
    """Roku-playable audio as-is: stereo AAC, or AC-3/E-AC-3 (any channel count,
    which the Roku bitstreams to the receiver for real surround)."""
    codec = info.get("audio_codec")
    if codec in ("ac3", "eac3"):
        return True
    return codec in ("aac", "mp4a") and info.get("channels", 0) <= 2


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


def clear_trailer(movie_id: int) -> None:
    """Drop the cached trailer so it re-downloads (e.g. after a manual override)."""
    trailer_file(movie_id).unlink(missing_ok=True)


def _youtube_key(s: str) -> str | None:
    """Pull the video key out of a YouTube URL, or pass a bare key through."""
    s = (s or "").strip()
    if "watch?v=" in s:
        s = s.split("watch?v=", 1)[1].split("&", 1)[0]
    elif "youtu.be/" in s:
        s = s.split("youtu.be/", 1)[1].split("?", 1)[0]
    return s or None


async def _ranked_trailer_keys(tmdb_id: int) -> list:
    """Candidate YouTube keys, best first: real Trailer > US > official > size."""
    if tmdb_id in _key_cache:
        return _key_cache[tmdb_id]
    videos = await get_movie_videos(tmdb_id)

    def _score(v: dict) -> tuple:
        return (
            1 if v.get("type") == "Trailer" else 0,
            1 if v.get("region") == "US" else 0,
            1 if v.get("official") else 0,
            v.get("size") or 0,
        )

    ranked = [
        v["key"] for v in sorted(videos, key=_score, reverse=True) if v.get("key")
    ]
    _key_cache[tmdb_id] = ranked
    return ranked


def _probe_sync(path: Path) -> dict | None:
    fp = ffprobe_path()
    if not fp:
        return None
    args = [
        fp, "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ]
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=60, creationflags=_LOWPRI
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    streams = data.get("streams", [])
    fmt = data.get("format", {})
    v = next((s for s in streams if s.get("codec_type") == "video"), None)
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)
    dur = float(fmt.get("duration") or 0)
    size = float(fmt.get("size") or 0)
    br = float(fmt.get("bit_rate") or 0)
    if br <= 0 and dur > 0 and size > 0:
        br = size * 8 / dur
    return {
        "height": int((v or {}).get("height") or 0),
        "bitrate": br,
        "audio_codec": (a or {}).get("codec_name"),
        "channels": int((a or {}).get("channels") or 0),
        "has_audio": a is not None,
    }


def _good_quality(info: dict | None) -> bool:
    """Reject potato uploads: real HD height + enough bitrate that it's not mush."""
    if info is None or not info.get("has_audio"):
        return False
    h = info.get("height") or 0
    if h < 720:
        return False
    # ~1.5 kbps per line of resolution: 720p~1.1Mbps, 1080p~1.6Mbps, 2160p~3.2Mbps.
    return info.get("bitrate", 0) >= h * 1500


async def _download(movie_id: int, key: str) -> bool:
    """Pull one trailer key to <id>.mkv. Returns True if a file landed."""
    ytdlp = yt_dlp_path()
    if not ytdlp:
        return False
    cap = max(480, get_settings().trailer_max_height)
    # Highest VP9 in [720, cap] (exclude AV1 — the 4802 can't decode it), AAC audio
    # preferred. -S res picks 4K over 1080 when a real 4K upload exists.
    fmt = (
        f"bv*[height>=720][height<={cap}][vcodec!*=av01]+ba[ext=m4a]/"
        f"bv*[height>=720][height<={cap}][vcodec!*=av01]+ba/"
        f"b[height>=720][height<={cap}][vcodec!*=av01]/b[height>=720][height<={cap}]"
    )
    args = [
        ytdlp, "--ignore-config",
        "-f", fmt, "-S", "res,vcodec:vp9",
        "--no-playlist",
        "--merge-output-format", "mkv", "--remux-video", "mkv",
        "-o", str(trailers_dir() / f"{movie_id}.%(ext)s"),
        f"https://www.youtube.com/watch?v={key}",
    ]
    ff = ffmpeg_path()
    if ff:
        args[1:1] = ["--ffmpeg-location", ff]

    # subprocess.run in a thread, NOT asyncio subprocess: the app forces a
    # SelectorEventLoop (psycopg) which can't spawn async subprocesses on Windows.
    def _run() -> subprocess.CompletedProcess:
        return subprocess.run(
            args, capture_output=True, text=True, timeout=600, creationflags=_LOWPRI
        )

    try:
        await asyncio.to_thread(_run)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return is_cached(movie_id)


async def _to_ac3(movie_id: int) -> None:
    """Re-encode the audio to AC-3 in place (video copied). Preserves the channel
    layout (5.1 stays 5.1) — the Roku bitstreams AC-3 to the receiver for real
    surround, and it plays where Opus / multichannel AAC went silent."""
    ff = ffmpeg_path()
    if not ff:
        return
    src = trailer_file(movie_id)
    tmp = trailers_dir() / f"{movie_id}.ac3.mkv"
    # First video + first audio only (drop extra/data streams that can fail the
    # remux). AC-3 at 640k carries 5.1 cleanly; channel count is preserved.
    args = [
        ff, "-y", "-i", str(src),
        "-map", "0:v:0", "-map", "0:a:0",
        "-c:v", "copy", "-c:a", "ac3", "-b:a", "640k",
        str(tmp),
    ]

    def _run() -> subprocess.CompletedProcess:
        return subprocess.run(
            args, capture_output=True, text=True, timeout=300, creationflags=_LOWPRI
        )

    try:
        proc = await asyncio.to_thread(_run)
    except (subprocess.TimeoutExpired, OSError):
        tmp.unlink(missing_ok=True)
        return
    if proc.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
        src.unlink(missing_ok=True)
        tmp.rename(src)
    else:
        tmp.unlink(missing_ok=True)


async def ensure_trailer(
    movie_id: int, tmdb_id: int | None, override: str | None = None
) -> Path | None:
    """Cache + return a good trailer for a movie, or None. A manual `override`
    (YouTube URL/key) is trusted and skips the quality gate; otherwise we try the
    ranked candidates and keep the first that passes the bitrate/audio check."""
    if is_cached(movie_id):
        return trailer_file(movie_id)
    if not yt_dlp_path():
        return None

    if override:
        key = _youtube_key(override)
        candidates, gated = ([key] if key else []), False
    elif tmdb_id:
        candidates, gated = (await _ranked_trailer_keys(tmdb_id))[:_MAX_CANDIDATES], True
    else:
        return None
    if not candidates:
        return None

    lock = _locks.setdefault(movie_id, asyncio.Lock())
    async with lock:
        if is_cached(movie_id):  # filled while we waited on the lock
            return trailer_file(movie_id)
        # Cap concurrency so a whole featured set doesn't thrash the box at once.
        async with _download_sem:
            if is_cached(movie_id):
                return trailer_file(movie_id)
            for key in candidates:
                if not key or not await _download(movie_id, key):
                    clear_trailer(movie_id)
                    continue
                info = await _probe(trailer_file(movie_id))
                if gated and not _good_quality(info):
                    clear_trailer(movie_id)  # potato — try the next candidate
                    continue
                # Fix Roku-unplayable audio (Opus, or multichannel AAC which the
                # 4802 silences) by transcoding to AC-3 — keeps 5.1 surround and
                # bitstreams to the Denon.
                if info and not _audio_ok(info):
                    await _to_ac3(movie_id)
                return trailer_file(movie_id)
    return None


async def _probe(path: Path) -> dict | None:
    return await asyncio.to_thread(_probe_sync, path)
