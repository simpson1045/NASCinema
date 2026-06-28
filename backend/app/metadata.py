"""TMDB metadata lookup. Degrades gracefully: with no API key it returns None
and the scanner falls back to the parsed filename."""

from __future__ import annotations

from difflib import SequenceMatcher

import httpx

from .config import get_settings

TMDB_BASE = "https://api.themoviedb.org/3"


def _confidence(parsed_title: str, tmdb_title: str) -> float:
    a = parsed_title.strip().lower()
    b = (tmdb_title or "").strip().lower()
    if not a or not b:
        return 0.0
    return round(SequenceMatcher(None, a, b).ratio(), 3)


async def get_movie_metadata(title: str, year: int | None = None) -> dict | None:
    """Search TMDB for a movie, then fetch details for runtime + genres."""
    key = get_settings().tmdb_api_key
    if not key:
        return None

    params: dict = {"api_key": key, "query": title, "include_adult": "false"}
    if year:
        params["year"] = year

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            search = await client.get(f"{TMDB_BASE}/search/movie", params=params)
            search.raise_for_status()
            results = search.json().get("results", [])
            if not results:
                return None
            best = results[0]

            details = await client.get(
                f"{TMDB_BASE}/movie/{best['id']}", params={"api_key": key}
            )
            details.raise_for_status()
            detail = details.json()
    except (httpx.HTTPError, KeyError, ValueError):
        return None

    release = best.get("release_date") or ""
    return {
        "tmdb_id": best["id"],
        "title": best.get("title") or title,
        "original_title": best.get("original_title"),
        "year": int(release[:4]) if release[:4].isdigit() else year,
        "overview": best.get("overview"),
        "rating": best.get("vote_average"),
        "poster_path": best.get("poster_path"),
        "backdrop_path": best.get("backdrop_path"),
        "runtime": detail.get("runtime"),
        "genres": [g["name"] for g in detail.get("genres", [])],
        "match_confidence": _confidence(title, best.get("title") or ""),
    }


# tmdb_id -> clearlogo URL (or None). Cached for the process so the play path
# only hits TMDB once per movie. None is cached too (movie has no logo); only
# transient fetch failures are left uncached so a later play can retry.
_logo_cache: dict[int, str | None] = {}


async def get_movie_logo(tmdb_id: int) -> str | None:
    """A movie's clearlogo (transparent PNG, ~JF-style) URL, or None."""
    if tmdb_id in _logo_cache:
        return _logo_cache[tmdb_id]
    key = get_settings().tmdb_api_key
    if not key:
        return None
    try:
        # Short timeout: this rides the play decision, so a slow TMDB must not
        # stall playback — we just skip the logo.
        async with httpx.AsyncClient(timeout=6) as client:
            r = await client.get(
                f"{TMDB_BASE}/movie/{tmdb_id}/images",
                params={"api_key": key, "include_image_language": "en,null"},
            )
            r.raise_for_status()
            logos = r.json().get("logos", [])
    except (httpx.HTTPError, ValueError):
        return None  # uncached — retry on a later play

    url: str | None = None
    if logos:
        # Prefer English, then PNG (renders cleaner than SVG on the TV), then the
        # most-voted.
        def _score(lg: dict) -> tuple:
            fp = str(lg.get("file_path", "")).lower()
            return (
                1 if lg.get("iso_639_1") == "en" else 0,
                1 if fp.endswith(".png") else 0,
                lg.get("vote_average") or 0,
            )

        best = max(logos, key=_score)
        fp = best.get("file_path")
        if fp:
            url = f"https://image.tmdb.org/t/p/w500{fp}"
    _logo_cache[tmdb_id] = url
    return url


async def get_movie_videos(tmdb_id: int) -> list[dict]:
    """Official trailers/clips for a movie (YouTube-hosted) from TMDB."""
    key = get_settings().tmdb_api_key
    if not key:
        return []
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{TMDB_BASE}/movie/{tmdb_id}/videos", params={"api_key": key}
            )
            r.raise_for_status()
            results = r.json().get("results", [])
    except (httpx.HTTPError, ValueError):
        return []

    videos = [
        {
            "name": v.get("name"),
            "type": v.get("type"),
            "key": v["key"],
            "url": f"https://www.youtube.com/watch?v={v['key']}",
        }
        for v in results
        if v.get("site") == "YouTube" and v.get("key")
    ]
    # Trailers first, then teasers/clips/featurettes.
    order = {"Trailer": 0, "Teaser": 1, "Clip": 2, "Featurette": 3}
    videos.sort(key=lambda v: order.get(v["type"], 9))
    return videos
