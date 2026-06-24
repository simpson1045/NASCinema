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
