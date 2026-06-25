"""OpenSubtitles (api.opensubtitles.com) search + download.

Degrades to empty results when no API key is set, like the TMDB client. All
network calls are async (httpx); the only blocking bit is the moviehash file
read, which callers run via asyncio.to_thread.
"""

from __future__ import annotations

import os
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
    }


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
    return "WEBVTT\n\n" + text.lstrip("﻿")
