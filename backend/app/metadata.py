"""TMDB metadata lookup. Degrades gracefully: with no API key it returns None
and the scanner falls back to the parsed filename."""

from __future__ import annotations

import asyncio

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


def _norm(s: str) -> str:
    return "".join(c for c in (s or "").lower() if c.isalnum())


def _pick(results: list[dict], title: str, year: int | None) -> dict:
    """Choose the TMDB result that IS this movie, not just the first/most
    popular: an exact (punctuation-blind) title match wins, then the release
    year, then TMDB's own order. "Jurassic World" must not become "Jurassic
    World Rebirth"; "...Deathly Hallows Part 2" must not become Part 1."""
    want = _norm(title)

    def score(i_r: tuple[int, dict]) -> tuple:
        i, r = i_r
        names = {_norm(r.get("title", "")), _norm(r.get("original_title", ""))}
        released = (r.get("release_date") or "")[:4]
        return (
            want in names,
            bool(year) and released == str(year),
            -i,
        )

    return max(enumerate(results), key=score)[1]


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
            best = _pick(results, title, year)

            details = await client.get(
                f"{TMDB_BASE}/movie/{best['id']}",
                params={"api_key": key, "append_to_response": "release_dates"},
            )
            details.raise_for_status()
            detail = details.json()
    except (httpx.HTTPError, KeyError, ValueError):
        return None

    release = best.get("release_date") or ""
    collection = detail.get("belongs_to_collection") or {}
    return {
        "tmdb_id": best["id"],
        "title": best.get("title") or title,
        "original_title": best.get("original_title"),
        "year": int(release[:4]) if release[:4].isdigit() else year,
        "overview": best.get("overview"),
        "rating": detail.get("vote_average") or best.get("vote_average"),
        "poster_path": best.get("poster_path"),
        "backdrop_path": best.get("backdrop_path"),
        "runtime": detail.get("runtime"),
        "genres": [g["name"] for g in detail.get("genres", [])],
        "match_confidence": _confidence(title, best.get("title") or ""),
        # Ranking + grouping signals (free from the details response).
        "popularity": detail.get("popularity") or best.get("popularity"),
        "vote_count": detail.get("vote_count") or best.get("vote_count"),
        "imdb_id": detail.get("imdb_id") or None,
        "collection_id": collection.get("id"),
        "certification": _certification(detail),
        "collection_name": collection.get("name"),
    }


async def get_movie_metadata_by_id(tmdb_id: int) -> dict | None:
    """Fetch the ranking/grouping signals for a known TMDB id (no search step).

    Used by the ratings backfill on already-matched movies. Returns the enrichment
    fields only — title/poster/etc. are left to the original match.
    """
    key = get_settings().tmdb_api_key
    if not key or not tmdb_id:
        return None
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{TMDB_BASE}/movie/{tmdb_id}",
                params={"api_key": key, "append_to_response": "release_dates"},
            )
            r.raise_for_status()
            detail = r.json()
    except (httpx.HTTPError, ValueError):
        return None
    collection = detail.get("belongs_to_collection") or {}
    return {
        "popularity": detail.get("popularity"),
        "vote_count": detail.get("vote_count"),
        "rating": detail.get("vote_average"),
        "imdb_id": detail.get("imdb_id") or None,
        "collection_id": collection.get("id"),
        "certification": _certification(detail),
        "collection_name": collection.get("name"),
    }


async def get_omdb_ratings(imdb_id: str) -> dict | None:
    """IMDB / Rotten Tomatoes / Metacritic scores for an IMDB id, via OMDb.

    Opt-in: returns None with no OMDb key. RT coverage is partial (OMDb only has
    it for some titles), so any of the three may be absent for a given film.
    """
    key = get_settings().omdb_api_key
    if not key or not imdb_id:
        return None
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                "https://www.omdbapi.com/",
                params={"apikey": key, "i": imdb_id},
            )
            r.raise_for_status()
            data = r.json()
    except (httpx.HTTPError, ValueError):
        return None
    if data.get("Response") != "True":
        return None

    def _num(v: str | None) -> float | None:
        try:
            return float(str(v).split("/")[0])
        except (TypeError, ValueError):
            return None

    rt: int | None = None
    for src in data.get("Ratings", []):
        if src.get("Source") == "Rotten Tomatoes":
            pct = str(src.get("Value", "")).rstrip("%")
            rt = int(pct) if pct.isdigit() else None

    meta = data.get("Metascore")
    return {
        "imdb_rating": _num(data.get("imdbRating")),
        "rt_score": rt,
        "metacritic": int(meta) if str(meta).isdigit() else None,
    }


def _certification(detail: dict) -> str:
    """The movie's content rating in the configured region (PG-13, R, 12A…)
    from TMDB's release dates — theatrical first. "" = none published (kept
    distinct from NULL = not looked up yet)."""
    region = (get_settings().rating_region or "us").strip().upper()
    for country in (detail.get("release_dates") or {}).get("results", []):
        if country.get("iso_3166_1") != region:
            continue
        dates = country.get("release_dates", [])
        # TMDB types: 3 theatrical, 2 limited, 1 premiere, 4 digital, 5 physical.
        for kind in (3, 2, 1, 4, 5, 6):
            for d in dates:
                if d.get("type") == kind and (d.get("certification") or "").strip():
                    return d["certification"].strip()
    return ""


# tmdb_id -> {"url": clearlogo URL or None, "series": bool}. Cached for the
# process so the play path only hits TMDB once per movie. Transient fetch
# failures are left uncached so a later request can retry.
_logo_cache: dict[int, dict] = {}
# tmdb_id -> set of that movie's logo file paths (for collection comparison).
_logo_paths: dict[int, set[str]] = {}
# collection id -> member tmdb ids.
_collection_parts: dict[int, list[int]] = {}


async def _sibling_logo_paths(client: httpx.AsyncClient, key: str,
                              collection_id: int, tmdb_id: int) -> set[str]:
    """Every logo file used by the OTHER movies in a collection. TMDB reuses one
    file across a franchise for its series wordmark (13 of 14 Land Before Time
    movies share one), so a path found here is the series logo, not this
    movie's."""
    parts = _collection_parts.get(collection_id)
    if parts is None:
        r = await client.get(f"{TMDB_BASE}/collection/{collection_id}",
                             params={"api_key": key})
        r.raise_for_status()
        parts = [p["id"] for p in r.json().get("parts", []) if p.get("id")]
        _collection_parts[collection_id] = parts

    async def paths(mid: int) -> set[str]:
        if mid not in _logo_paths:
            r = await client.get(f"{TMDB_BASE}/movie/{mid}/images",
                                 params={"api_key": key,
                                         "include_image_language": "en,null"})
            r.raise_for_status()
            _logo_paths[mid] = {lg["file_path"] for lg in r.json().get("logos", [])
                                if lg.get("file_path")}
        return _logo_paths[mid]

    found: set[str] = set()
    for fp in await asyncio.gather(*(paths(m) for m in parts if m != tmdb_id)):
        found |= fp
    return found


async def get_movie_logo_info(tmdb_id: int) -> dict:
    """A movie's clearlogo URL plus `series`: True when the best available logo
    is the franchise's shared wordmark rather than this movie's own (the apps
    then print the subtitle — "VIII · The Big Freeze" — under it)."""
    if tmdb_id in _logo_cache:
        return _logo_cache[tmdb_id]
    key = get_settings().tmdb_api_key
    if not key:
        return {"url": None, "series": False}
    try:
        # Short timeouts: this rides the play decision, so a slow TMDB must
        # not stall playback — we just skip the logo.
        async with httpx.AsyncClient(timeout=6) as client:
            r = await client.get(
                f"{TMDB_BASE}/movie/{tmdb_id}",
                params={"api_key": key, "append_to_response": "images",
                        "include_image_language": "en,null"},
            )
            r.raise_for_status()
            data = r.json()
            logos = (data.get("images") or {}).get("logos", [])
            shared: set[str] = set()
            col = (data.get("belongs_to_collection") or {}).get("id")
            if col and logos:
                try:
                    shared = await asyncio.wait_for(
                        _sibling_logo_paths(client, key, col, tmdb_id), timeout=8)
                except (httpx.HTTPError, ValueError, asyncio.TimeoutError):
                    shared = set()  # can't tell — fall back to the plain pick
    except (httpx.HTTPError, ValueError):
        return {"url": None, "series": False}  # uncached — retry later

    info = {"url": None, "series": False}
    if logos:
        # English first (an untagged logo can be a foreign title — Land Before
        # Time VIII's was Portuguese, for a different sequel), then this movie's
        # own logo over a franchise-shared one, then PNG, then most-voted.
        def _score(lg: dict) -> tuple:
            fp = str(lg.get("file_path", ""))
            return (
                1 if lg.get("iso_639_1") == "en" else 0,
                0 if fp in shared else 1,
                1 if fp.lower().endswith(".png") else 0,
                lg.get("vote_average") or 0,
            )

        best = max(logos, key=_score)
        fp = best.get("file_path")
        if fp:
            info = {"url": f"https://image.tmdb.org/t/p/w500{fp}",
                    "series": fp in shared}
    _logo_cache[tmdb_id] = info
    return info


async def get_movie_logo(tmdb_id: int) -> str | None:
    """A movie's clearlogo (transparent PNG, ~JF-style) URL, or None."""
    return (await get_movie_logo_info(tmdb_id))["url"]


def logo_subtitle(title: str, collection_name: str | None) -> str | None:
    """What to print under a franchise-wide logo: the part of the title that
    names THIS movie. "The Land Before Time VIII: The Big Freeze" in "The Land
    Before Time Collection" -> "VIII · The Big Freeze"."""
    base = (collection_name or "").strip()
    for suffix in (" Collection", " collection", " Series", " Trilogy"):
        if base.endswith(suffix):
            base = base[: -len(suffix)].strip()
    rest = title
    if base and title.lower().startswith(base.lower()):
        rest = title[len(base):]
    rest = rest.strip(" :-–—").replace(": ", " · ")
    # "Harry Potter and the Chamber of Secrets" -> "The Chamber of Secrets"
    for joiner in ("and ", "& ", "of "):
        if rest.lower().startswith(joiner):
            rest = rest[len(joiner):]
    return (rest[:1].upper() + rest[1:]) if rest else None


async def get_movie_videos(tmdb_id: int) -> list[dict]:
    """Official trailers/clips for a movie (YouTube-hosted) from TMDB."""
    key = get_settings().tmdb_api_key
    if not key:
        return []
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{TMDB_BASE}/movie/{tmdb_id}/videos",
                params={"api_key": key, "language": "en-US"},
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
            # Kept so trailer selection can prefer the US/official upload.
            "official": bool(v.get("official")),
            "region": v.get("iso_3166_1"),
            "size": v.get("size") or 0,
        }
        for v in results
        if v.get("site") == "YouTube" and v.get("key")
    ]
    # Trailers first, then teasers/clips/featurettes.
    order = {"Trailer": 0, "Teaser": 1, "Clip": 2, "Featurette": 3}
    videos.sort(key=lambda v: order.get(v["type"], 9))
    return videos
