"""OpenSubtitles (api.opensubtitles.com) search + download.

Degrades to empty results when no API key is set, like the TMDB client. All
network calls are async (httpx); the only blocking bit is the moviehash file
read, which callers run via asyncio.to_thread.
"""

from __future__ import annotations

import os
import math
import re
import struct

import httpx

from . import __version__
from .config import get_settings

OS_BASE = "https://api.opensubtitles.com/api/v1"
_TS = re.compile(r"(\d{2}:\d{2}:\d{2}),(\d{3})")


def _headers() -> dict:
    return {
        "Api-Key": get_settings().opensubtitles_api_key,
        "User-Agent": f"NASCinema v{__version__}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def compute_moviehash(path: str) -> str | None:
    """OpenSubtitles' moviehash: filesize + 64-bit checksums of the first and
    last 64 KiB. Yields exact, perfectly-synced matches for a specific rip."""
    fmt = "<q"
    word = struct.calcsize(fmt)
    chunk = 65536
    try:
        size = os.path.getsize(path)
        if size < chunk * 2:
            return None
        h = size
        with open(path, "rb") as f:
            for _ in range(chunk // word):
                (val,) = struct.unpack(fmt, f.read(word))
                h = (h + val) & 0xFFFFFFFFFFFFFFFF
            f.seek(size - chunk)
            for _ in range(chunk // word):
                (val,) = struct.unpack(fmt, f.read(word))
                h = (h + val) & 0xFFFFFFFFFFFFFFFF
        return f"{h:016x}"
    except (OSError, struct.error):
        return None


def _normalize(item: dict) -> dict | None:
    a = item.get("attributes") or {}
    files = a.get("files") or []
    if not files or not files[0].get("file_id"):
        return None
    feature = a.get("feature_details") or {}
    return {
        "os_file_id": files[0]["file_id"],
        "language": a.get("language") or "und",
        "release": a.get("release") or feature.get("movie_name") or "",
        "downloads": a.get("download_count") or 0,
        "hearing_impaired": bool(a.get("hearing_impaired")),
        "from_trusted": bool(a.get("from_trusted")),
        "fps": a.get("fps"),
        "machine_translated": bool(a.get("machine_translated") or a.get("ai_translated")),
    }


_HD_SRC = re.compile(r"blu-?ray|bd-?rip|br-?rip|bd-?remux|remux|web-?dl|web-?rip|webrip|"
                     r"\b(720|1080|2160)p\b|\buhd\b|hdtv", re.I)
_SD_SRC = re.compile(r"\bdvd|xvid|divx|\bvhs\b|\(v\)|tv-?rip|\bntsc\b|\bpal\b|"
                     r"\b(480|576)p\b|vcd", re.I)


_STOP = {"the", "and", "of", "a", "an", "part", "ii", "iii", "iv"}


def _words(s: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", s.lower().replace("'", "")) if w not in _STOP}


def rank(results: list[dict], *, file_height: int | None,
         title: str | None = None) -> list[dict]:
    """Order title-search results by how likely each is synced to THIS file,
    not by popularity: OpenSubtitles' download_count put a VHS-era SDH file
    on top for a Blu-ray of Lion King II (off by 15-45 s), while a trusted
    Blu-ray release ten rows down was perfect (2026-10-02). Adds `tags` and
    `best` for the UI. Exact moviehash matches always lead."""
    hd_file = (file_height or 0) >= 700
    want = {w for w in _words(title or "") if len(w) >= 3}
    for r in results:
        rel = r.get("release") or ""
        tags, score = [], 0.0
        # The title search also returns other films ("Species II", "The
        # Prophecy II" for Lion King II): the release must name this movie.
        if want and not r.get("exact"):
            hit = len(want & _words(rel)) / len(want)
            if hit < 0.5:
                tags.append("Other movie?")
                score -= 200
        if r.get("exact"):
            tags.append("Exact match")
            score += 1000
        if _HD_SRC.search(rel):
            tags.append("Blu-ray/WEB" if re.search(r"blu|bd|remux|web", rel, re.I) else "HD")
            score += 40 if hd_file else -10
        elif _SD_SRC.search(rel):
            tags.append("DVD/TV")
            score += -40 if hd_file else 20
        fps = r.get("fps")
        if hd_file and fps and abs(float(fps) - 25.0) < 0.1:
            tags.append("25 fps")
            score -= 30  # PAL timing on a 23.976 Blu-ray drifts ~4%
        if r.get("from_trusted"):
            tags.append("Trusted")
            score += 15
        if r.get("hearing_impaired"):
            tags.append("SDH")
            score -= 10
        if r.get("machine_translated"):
            tags.append("Machine-translated")
            score -= 100
        score += math.log10((r.get("downloads") or 0) + 1) * 5  # tiebreak only
        r["tags"], r["score"] = tags, round(score, 1)
    results.sort(key=lambda r: r["score"], reverse=True)
    for i, r in enumerate(results):
        r["best"] = i == 0
    return results


async def _query(client: httpx.AsyncClient, params: dict) -> list[dict]:
    try:
        r = await client.get(f"{OS_BASE}/subtitles", params=params, headers=_headers())
        r.raise_for_status()
        data = r.json().get("data", [])
    except (httpx.HTTPError, ValueError):
        return []
    return [r for r in (_normalize(it) for it in data) if r]


async def search(
    *,
    query: str | None,
    year: int | None,
    languages: str = "en",
    moviehash: str | None = None,
) -> list[dict]:
    """Exact file-hash match first (synced to this exact rip); fall back to
    title/year if the hash isn't in their DB (common for specific 4K rips)."""
    if not get_settings().opensubtitles_api_key:
        return []
    async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
        if moviehash:
            hashed = await _query(client, {"languages": languages, "moviehash": moviehash})
            if hashed:
                for h in hashed:
                    h["exact"] = True
                return hashed
        params: dict = {"languages": languages, "order_by": "download_count"}
        if query:
            params["query"] = query
        if year:
            params["year"] = year
        return await _query(client, params)


async def download_srt(os_file_id: int) -> bytes | None:
    """POST /download for a temporary link, then fetch the subtitle bytes."""
    if not get_settings().opensubtitles_api_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            r = await client.post(
                f"{OS_BASE}/download",
                headers=_headers(),
                json={"file_id": os_file_id},
            )
            r.raise_for_status()
            link = r.json().get("link")
            if not link:
                return None
            sub = await client.get(link)
            sub.raise_for_status()
            return sub.content
    except (httpx.HTTPError, ValueError):
        return None


def srt_to_vtt(raw: bytes) -> str:
    """SRT bytes -> WebVTT text: decode, normalise newlines, swap the cue
    timestamp comma for a period, prepend the WEBVTT header."""
    text = None
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        text = raw.decode("utf-8", errors="replace")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _TS.sub(r"\1.\2", text)
    # MicroDVD/ASS leftovers ({Y:i}, {\\an8}) show up as literal text in VTT.
    text = re.sub(r"\{[^}\n]{1,40}\}", "", text)
    return "WEBVTT\n\n" + text.lstrip("﻿")
