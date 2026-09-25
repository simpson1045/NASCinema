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
import time
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

    # Trailers and teasers only — TMDB also lists clips and featurettes.
    ranked = [
        v["key"]
        for v in sorted(videos, key=_score, reverse=True)
        if v.get("key") and v.get("type") in ("Trailer", "Teaser")
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
        "width": int((v or {}).get("width") or 0),
        "video_codec": (v or {}).get("codec_name"),
        "duration": dur,
        "bitrate": br,
        "audio_codec": (a or {}).get("codec_name"),
        "channels": int((a or {}).get("channels") or 0),
        "has_audio": a is not None,
    }


# The quality bar. On a 77" OLED a 1-2 Mbps 1080p trailer is visible mush, so:
# at least 1080 lines, and ~2.8 kbps per line for H.264 (1080p >= 3.0 Mbps,
# 2160p >= 6.0). VP9 looks as good at ~70% of that bitrate, so it gets 0.7x.
_MIN_HEIGHT = 1080
_BPS_PER_LINE = 2800
_VP9_FACTOR = 0.7


def _min_bitrate(height: int, codec: str | None) -> float:
    factor = _VP9_FACTOR if (codec or "").startswith("vp") else 1.0
    return height * _BPS_PER_LINE * factor


def _lines(width: int | None, height: int | None) -> int:
    """16:9-equivalent lines: a scope trailer stored cropped at 1920x800 is
    1080p, not 800p (judging by raw height rejected good widescreen ones)."""
    w, h = width or 0, height or 0
    return max(h, round(w * 9 / 16))


def _good_quality(info: dict | None) -> bool:
    """Reject mush: real 1080p+ and enough bitrate for the codec."""
    if info is None or not info.get("has_audio"):
        return False
    h = _lines(info.get("width"), info.get("height"))
    if h < _MIN_HEIGHT:
        return False
    return info.get("bitrate", 0) >= _min_bitrate(h, info.get("video_codec"))


async def _download(movie_id: int, key: str) -> bool:
    """Pull one trailer key to <id>.mkv. Returns True if a file landed."""
    ytdlp = yt_dlp_path()
    if not ytdlp:
        return False
    cap = max(480, get_settings().trailer_max_height)
    # Highest resolution in [720, cap], then the highest-bitrate stream at it
    # (exclude AV1 — the 4802 can't decode it), AAC audio preferred. At 1080p
    # YouTube's H.264 stream is often ~4x the VP9 one, so bitrate — not codec —
    # breaks the tie (matches how _offer_sync ranks candidates).
    # No HLS (m3u8) formats: they arrive as MPEG-TS whose timestamps the MKV
    # merge rejects ("Error muxing a packet") — the DASH copy of the same
    # stream merges cleanly.
    v = f"[height>=720][height<={cap}][vcodec!*=av01][protocol!*=m3u8]"
    fmt = f"bv*{v}+ba[ext=m4a]/bv*{v}+ba/b{v}"
    args = [
        ytdlp, "--ignore-config",
        "-f", fmt, "-S", "res,br",
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


# --- Picking the best trailer ------------------------------------------------
# TMDB lists several trailers per movie and YouTube often has 4K re-release cuts
# TMDB doesn't. Instead of taking the first that passes, ask YouTube what each
# candidate actually offers (no download) and pull the sharpest.

_SEARCH_RESULTS = 10
_NO_TRAILER_DAYS = 7  # after finding nothing good, don't re-search on every load
_JUNK_WORDS = ("reaction", "review", "fan made", "fanmade", "concept", "explained",
               "honest trailer", "parody", "breakdown", "recap", "scene", "clip",
               # AI upscales / frame interpolation look plasticky — official only
               "enhanced", "upscale", "remastered by", "60fps", "interpolat")


def _none_file(movie_id: int) -> Path:
    return trailers_dir() / f"{movie_id}.none.json"


def _recently_found_nothing(movie_id: int) -> bool:
    f = _none_file(movie_id)
    try:
        return (time.time() - f.stat().st_mtime) < _NO_TRAILER_DAYS * 86400
    except OSError:
        return False


def _ytdlp_json(ref: str, flat: bool = False) -> dict | None:
    ytdlp = yt_dlp_path()
    if not ytdlp:
        return None
    args = [ytdlp, "--ignore-config", "-J", "--skip-download", "--no-warnings"]
    if flat:
        args.append("--flat-playlist")
    args.append(ref)
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=90, creationflags=_LOWPRI
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def _offer_sync(key: str) -> dict | None:
    """What a YouTube video offers, without downloading: the best non-AV1 video
    height (capped) and that format's bitrate. None if unavailable."""
    info = _ytdlp_json(f"https://www.youtube.com/watch?v={key}")
    if not info:
        return None
    cap = max(480, get_settings().trailer_max_height)
    best = (0, 0.0)
    for f in info.get("formats") or []:
        vc = f.get("vcodec") or "none"
        h = _lines(f.get("width"), f.get("height"))
        if vc == "none" or vc.startswith("av01") or not (0 < h <= cap):
            continue
        if "m3u8" in (f.get("protocol") or ""):
            continue  # the downloader skips HLS too (see _download)
        # tbr is kbps; VP9 counts for more per bit, same as the quality gate.
        tbr = float(f.get("tbr") or f.get("vbr") or 0)
        if vc.startswith("vp"):
            tbr /= _VP9_FACTOR
        best = max(best, (h, tbr))
    if best[0] == 0:
        return None
    return {"key": key, "height": best[0], "kbps": best[1],
            "title": info.get("title") or "",
            "channel": info.get("channel") or info.get("uploader") or "",
            "duration": info.get("duration") or 0}


_SEQUEL_WORDS = {"2", "3", "4", "5", "6", "7", "8", "9", "ii", "iii", "iv", "v"}


def _words(text: str) -> list[str]:
    return "".join(c if c.isalnum() else " " for c in text.lower()).split()


def _names_this_movie(name: list[str], title: list[str]) -> bool:
    """The upload's name contains the title's words in order, and the next word
    isn't a sequel number ("Spider-Man 2" is not "Spider-Man"; "Terminator 2
    ... 35th Anniversary" and "(2002)" are fine)."""
    n = len(title)
    if n == 0:
        return False
    for i in range(len(name) - n + 1):
        if name[i:i + n] == title:
            nxt = name[i + n] if i + n < len(name) else ""
            return nxt not in _SEQUEL_WORDS
    return False


def _search_keys_sync(title: str, year: int | None) -> list[str]:
    """YouTube search for the movie's trailer, filtered to plausible official
    uploads: trailer-length, the title in the name, no reactions/reviews."""
    # One search's top 10 misses a lot (Chamber of Secrets' 4K uploads never
    # made it), so a few phrasings are merged.
    queries = [
        f"{title} {year or ''} official trailer 4K",
        f"{title} trailer 4K",
        f"{title} {year or ''} trailer",
    ]
    entries: list[dict] = []
    for q in queries:
        data = _ytdlp_json(f"ytsearch{_SEARCH_RESULTS}:{' '.join(q.split())}", flat=True)
        entries += (data or {}).get("entries") or []
    want = _words(title)
    keys = []
    for e in entries:
        name = (e.get("title") or "").lower()
        dur = e.get("duration") or 0
        if not e.get("id") or not (45 <= dur <= 300):
            continue
        if "trailer" not in name or any(w in name for w in _JUNK_WORDS):
            continue
        if not _names_this_movie(_words(name), want):
            continue
        # Another film's year in the name (a remake, a sequel) — skip it.
        years = {int(w) for w in _words(name)
                 if w.isdigit() and len(w) == 4 and 1900 <= int(w) <= 2100}
        if year and years and year not in years:
            continue
        keys.append(e["id"])
    return keys


async def _ranked_offers(tmdb_id: int | None, override: str | None) -> list[dict]:
    """OFFICIAL candidates only — the manual pick and TMDB's trailer list for
    this exact movie — probed and sorted: the manual pick first, then
    sharpest first. YouTube search is NOT used here: an
    upload's title proves nothing (Chamber of Secrets got the HBO series
    teaser titled "Chamber of Secrets 2002 Trailer 4K"). Search results are
    for a human-verified hunt only (search_offers)."""
    keys: list[str] = []
    manual = _youtube_key(override) if override else None
    if manual:
        keys.append(manual)
    if tmdb_id:
        keys += (await _ranked_trailer_keys(tmdb_id))[:_MAX_CANDIDATES + 3]
    seen: set[str] = set()
    unique = [k for k in keys if k and not (k in seen or seen.add(k))]
    offers = [o for o in await asyncio.gather(
        *(asyncio.to_thread(_offer_sync, k) for k in unique)) if o]

    # A manual pick is Matt's explicit choice: it always goes first (a 4K
    # re-release trailer must not beat the original he pinned).
    def score(o: dict) -> tuple:
        return (o["key"] == manual, o["height"], o["kbps"])

    return sorted(offers, key=score, reverse=True)


async def search_offers(title: str, year: int | None) -> list[dict]:
    """YouTube search candidates, probed and sorted sharpest first. NOT used
    automatically — only to hunt a sharper trailer that a human then checks
    (look at frames!) before pinning it as the movie's manual trailer."""
    keys = await asyncio.to_thread(_search_keys_sync, title, year)
    offers = [o for o in await asyncio.gather(
        *(asyncio.to_thread(_offer_sync, k) for k in dict.fromkeys(keys))) if o]
    return sorted(offers, key=lambda o: (o["height"], o["kbps"]), reverse=True)


def _source_file(movie_id: int) -> Path:
    return trailers_dir() / f"{movie_id}.source.json"


def trailer_source(movie_id: int) -> dict | None:
    """Where the cached trailer came from (video key/title/channel), if known."""
    try:
        data = json.loads(_source_file(movie_id).read_text())
    except (OSError, ValueError):
        return None
    return data if data.get("version") == trailer_version(movie_id) else None


async def ensure_trailer(
    movie_id: int,
    tmdb_id: int | None,
    override: str | None = None,
    title: str | None = None,
    year: int | None = None,
) -> Path | None:
    """Cache + return the sharpest OFFICIAL trailer for a movie, or None (the
    hero then shows the backdrop). One that clears the quality bar wins; if
    none does, the sharpest official one at 1080p+ is still used — the right
    movie beats pretty pixels. (title/year are accepted for callers but no
    longer drive a search.)"""
    if is_cached(movie_id):
        return trailer_file(movie_id)
    if not yt_dlp_path() or not (tmdb_id or override):
        return None
    if not override and _recently_found_nothing(movie_id):
        return None

    lock = _locks.setdefault(movie_id, asyncio.Lock())
    async with lock:
        if is_cached(movie_id):  # filled while we waited on the lock
            return trailer_file(movie_id)
        # Cap concurrency so a whole featured set doesn't thrash the box at once.
        async with _download_sem:
            if is_cached(movie_id):
                return trailer_file(movie_id)
            offers = await _ranked_offers(tmdb_id, override)
            manual = _youtube_key(override) if override else None
            tries = offers[:_MAX_CANDIDATES + 1]
            # The manual pick always gets a turn, even if it ranked lower.
            tries += [o for o in offers[_MAX_CANDIDATES + 1:] if o["key"] == manual]
            for offer in tries:
                pinned = offer["key"] == manual
                if await _fetch(movie_id, offer, require_bar=not pinned, pinned=pinned):
                    return trailer_file(movie_id)
            # Nothing cleared the bar: the sharpest official 1080p+ trailer.
            best = next((o for o in offers if o["height"] >= _MIN_HEIGHT), None)
            if best and await _fetch(movie_id, best, require_bar=False):
                return trailer_file(movie_id)
            _none_file(movie_id).write_text(json.dumps({"offers": len(offers)}))
    return None


async def _fetch(movie_id: int, offer: dict, require_bar: bool,
                 pinned: bool = False) -> bool:
    """Download one candidate; keep it if it passes (or the bar is waived)."""
    if not await _download(movie_id, offer["key"]):
        clear_trailer(movie_id)
        return False
    info = await _probe(trailer_file(movie_id))
    if require_bar and not _good_quality(info):
        clear_trailer(movie_id)  # mush — the caller tries the next one
        return False
    # Fix Roku-unplayable audio (Opus, or multichannel AAC which the 4802
    # silences) by transcoding to AC-3 — keeps 5.1 and bitstreams to the Denon.
    if info and not _audio_ok(info):
        await _to_ac3(movie_id)
    _none_file(movie_id).unlink(missing_ok=True)
    _source_file(movie_id).write_text(json.dumps({
        "version": trailer_version(movie_id), "key": offer["key"],
        "title": offer.get("title"), "channel": offer.get("channel"),
        # A pin is Matt's hand-checked pick (often a search find), not
        # necessarily from TMDB's official list — say which, for audits.
        "official": not pinned, "pinned": pinned,
    }))
    asyncio.create_task(measure_bars(movie_id))
    return True


async def _probe(path: Path) -> dict | None:
    return await asyncio.to_thread(_probe_sync, path)


# --- Letterbox detection -----------------------------------------------------
# Many trailers are 2.39:1 with black bars baked into a 16:9 frame. The TV never
# zooms or crops a trailer; it slides the video up so the top bar goes off-screen
# and the bottom bar sits under its own gradient. For that it needs the bar
# sizes, measured once per cached file with ffmpeg's cropdetect and kept in a
# <id>.bars.json sidecar tagged with the trailer's version (mtime).

_bars_pending: set[int] = set()
_bars_sem = asyncio.Semaphore(1)
_CROP_TOKEN = "crop="


def _bars_file(movie_id: int) -> Path:
    return trailers_dir() / f"{movie_id}.bars.json"


def trailer_bars(movie_id: int) -> dict | None:
    """{"top", "bottom"} bar heights as fractions of the frame height, or None if
    the current trailer file hasn't been measured yet."""
    try:
        data = json.loads(_bars_file(movie_id).read_text())
    except (OSError, ValueError):
        return None
    if data.get("version") != trailer_version(movie_id):
        return None
    return {"top": data.get("top", 0.0), "bottom": data.get("bottom", 0.0)}


def _cropdetect_sync(path: Path) -> dict | None:
    ff = ffmpeg_path()
    info = _probe_sync(path)
    if not ff or not info or not info["height"] or not info["width"]:
        return None
    width, height = info["width"], info["height"]
    # Skip the studio logos on black (first 20 s, or the first 15% of a short
    # clip), sample 30 s. reset=0 keeps growing the box to cover every non-black
    # pixel seen, so a bright scene anywhere in the window defines the edges.
    dur = info.get("duration") or 0
    first = 20.0 if dur <= 0 or dur > 60 else round(dur * 0.15, 1)
    for start in (str(first), "0"):
        args = [
            ff, "-hide_banner", "-nostats", "-ss", start, "-i", str(path),
            "-t", "30", "-an", "-sn",
            "-vf", "cropdetect=limit=24:round=2:reset=0", "-f", "null", "-",
        ]
        try:
            proc = subprocess.run(
                args, capture_output=True, text=True, timeout=120, creationflags=_LOWPRI
            )
        except (subprocess.TimeoutExpired, OSError):
            return None
        crops = [ln for ln in proc.stderr.splitlines() if _CROP_TOKEN in ln]
        try:
            w, h, _x, y = (
                int(v) for v in crops[-1].rsplit(_CROP_TOKEN, 1)[1].split()[0].split(":")
            )
        except (IndexError, ValueError):
            continue
        # An all-black window reports a negative/empty box — not a letterbox.
        # A real letterboxed picture is full width and at least ~40% tall.
        if w >= width * 0.9 and h >= height * 0.4 and y >= 0:
            break
    else:
        return {"top": 0.0, "bottom": 0.0}  # unmeasurable -> treat as full-frame
    # Measure against the 16:9 screen the TV shows it on: a 1920x800 file gets
    # bars from the player itself, on top of any baked into the picture.
    scale = min(16 / width, 9 / height)
    pad = (9 - height * scale) / 2
    top = max(0.0, (pad + y * scale) / 9)
    bottom = max(0.0, (pad + (height - y - h) * scale) / 9)
    # Under 2% is encoder noise / a thin edge, not a letterbox.
    return {
        "top": round(top, 4) if top >= 0.02 else 0.0,
        "bottom": round(bottom, 4) if bottom >= 0.02 else 0.0,
    }


async def measure_bars(movie_id: int, force: bool = False) -> None:
    """Measure + cache the current trailer's letterbox bars (no-op if done,
    unless `force` re-measures and overwrites)."""
    if movie_id in _bars_pending or not is_cached(movie_id):
        return
    if not force and trailer_bars(movie_id) is not None:
        return
    _bars_pending.add(movie_id)
    try:
        async with _bars_sem:
            version = trailer_version(movie_id)
            bars = await asyncio.to_thread(_cropdetect_sync, trailer_file(movie_id))
            if bars is not None and version == trailer_version(movie_id):
                _bars_file(movie_id).write_text(json.dumps({"version": version, **bars}))
    finally:
        _bars_pending.discard(movie_id)
