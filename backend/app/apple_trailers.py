"""Apple TV trailers — the first-choice trailer source.

Apple is a film distributor: its trailers are the studio's own cut (the real
theatrical trailer, not a 4K re-release promo or a fan upload), 7–25 Mbps,
5.1 AC-3 / Atmos, and HDR10+ when offered — YouTube tops out around 3 Mbps at
1080p. Trailers are not DRM-protected. Fully automatic, no account or key:

  TMDB id ──Wikidata (P4947 → P9586)──▶ Apple TV id (umc.cmc.…)
          ──tv.apple.com catalog API──▶ trailer HLS master playlist
          ──parse variants──▶ best HDR video, best SDR video, best audio
          ──ffmpeg -c copy──▶ <id>.mkv (+ <id>.sdr.mkv when the main is HDR)

Everything fails soft: no Wikidata match, catalog change, network trouble →
the caller falls back to YouTube. Be a polite client: one batched Wikidata
query per library (cached on disk, negatives retried after a month, backs off
when rate-limited), catalog tokens reused for hours.

Apple's catalog API is the one tv.apple.com's web app uses; it's unofficial,
so it can change — which is exactly why nothing here is load-bearing.
"""

from __future__ import annotations

import asyncio
import gzip
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from . import __version__
from .config import get_settings

_UA_BROWSER = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)
# Wikidata asks automated clients to identify themselves.
_UA_BOT = (
    f"NASCinema/{__version__} (self-hosted media server; "
    "https://github.com/simpson1045/NASCinema)"
)
_WIKIDATA = "https://query.wikidata.org/sparql"
_NEGATIVE_TTL = 30 * 86400  # re-ask Wikidata about unmatched movies monthly
_TOKEN_TTL = 6 * 3600
_OFFER_TTL = 6 * 3600
_BATCH = 150  # TMDB ids per SPARQL query

# Fallback storefront ids, used only if the region's page doesn't say.
_STOREFRONTS = {
    "us": "143441", "gb": "143444", "ca": "143455", "au": "143460",
    "de": "143443", "fr": "143442", "it": "143450", "es": "143454",
    "nl": "143452", "ie": "143449", "nz": "143461", "jp": "143462",
    "mx": "143468", "br": "143503", "se": "143456", "no": "143457",
    "dk": "143458", "fi": "143447", "be": "143446", "at": "143445",
    "ch": "143459", "in": "143467",
}

_wikidata_blocked_until = 0.0
_ids_lock = asyncio.Lock()
_tokens: tuple[float, dict] | None = None
_offers: dict[int, tuple[float, dict | None]] = {}


# --- HTTP ---------------------------------------------------------------------

def _get(url: str, ua: str = _UA_BROWSER, accept: str | None = None,
         timeout: int = 30) -> str:
    headers = {"User-Agent": ua, "Accept-Encoding": "gzip"}
    if accept:
        headers["Accept"] = accept
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers),
                                timeout=timeout) as r:
        body = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
    return body.decode("utf-8", "replace")


# --- TMDB id → Apple TV id (Wikidata) -----------------------------------------

def _ids_file() -> Path:
    from .trailers import trailers_dir  # local: trailers imports this module
    return trailers_dir() / "apple_ids.json"


def _load_ids() -> dict:
    try:
        return json.loads(_ids_file().read_text())
    except (OSError, ValueError):
        return {}


def _query_wikidata(tmdb_ids: list[str]) -> dict[str, str]:
    values = " ".join(f'"{t}"' for t in tmdb_ids)
    q = ("SELECT ?tmdb ?apple WHERE { VALUES ?tmdb { %s } "
         "?item wdt:P4947 ?tmdb . ?item wdt:P9586 ?apple }" % values)
    body = _get(f"{_WIKIDATA}?{urllib.parse.urlencode({'query': q})}", ua=_UA_BOT,
                accept="application/sparql-results+json", timeout=60)
    found: dict[str, str] = {}
    for b in json.loads(body)["results"]["bindings"]:
        found.setdefault(b["tmdb"]["value"], b["apple"]["value"])
    return found


async def resolve_ids(tmdb_ids: list[int]) -> dict[int, str | None]:
    """Apple TV ids for these TMDB ids — from the disk cache, asking Wikidata
    (batched) only for the unknown or long-unmatched ones."""
    global _wikidata_blocked_until
    async with _ids_lock:
        cache = _load_ids()
        now = time.time()
        wanted = [str(t) for t in dict.fromkeys(tmdb_ids) if t]
        missing = [t for t in wanted if t not in cache or (
            cache[t].get("umc") is None and now - cache[t].get("t", 0) > _NEGATIVE_TTL)]
        if missing and now >= _wikidata_blocked_until:
            try:
                for i in range(0, len(missing), _BATCH):
                    chunk = missing[i:i + _BATCH]
                    found = await asyncio.to_thread(_query_wikidata, chunk)
                    for t in chunk:
                        cache[t] = {"umc": found.get(t), "t": now}
                    if i + _BATCH < len(missing):
                        await asyncio.sleep(2)
            except urllib.error.HTTPError as e:
                # 429 = rate-limited (they've throttled to 1/min during outages).
                wait = int(e.headers.get("Retry-After") or 0) if e.code == 429 else 0
                _wikidata_blocked_until = now + max(wait, 120)
            except (urllib.error.URLError, OSError, ValueError, KeyError):
                _wikidata_blocked_until = now + 300
            try:
                _ids_file().write_text(json.dumps(cache))
            except OSError:
                pass
        return {int(t): (cache.get(t) or {}).get("umc") for t in wanted}


# --- Apple catalog: trailer playlist ------------------------------------------

def _region() -> str:
    return (get_settings().trailer_region or "us").strip().lower()


def _catalog_tokens_sync() -> dict:
    """Per-session params the tv.apple.com web app embeds in every page."""
    region = _region()
    page = _get(f"https://tv.apple.com/{region}")
    utsk = re.search(r'"utsk":"([^"]+)"', page)
    utscf = re.search(r'"utscf":"([^"]+)"', page)
    sf = re.search(r'"sf":"(\d+)"', page)
    if not (utsk and utscf):
        raise ValueError("tv.apple.com page carried no catalog tokens")
    return {"utsk": utsk.group(1), "utscf": utscf.group(1),
            "sf": sf.group(1) if sf else _STOREFRONTS.get(region, "143441")}


async def _catalog_tokens(refresh: bool = False) -> dict:
    global _tokens
    if refresh or not _tokens or time.time() - _tokens[0] > _TOKEN_TTL:
        _tokens = (time.time(), await asyncio.to_thread(_catalog_tokens_sync))
    return _tokens[1]


def _trailer_hls_sync(umc: str, tok: dict) -> tuple[str | None, str | None]:
    params = urllib.parse.urlencode({
        "caller": "web", "sf": tok["sf"], "v": "90", "pfm": "web",
        "locale": get_settings().trailer_locale or "en-US",
        "utscf": tok["utscf"], "utsk": tok["utsk"]})
    d = json.loads(_get(f"https://tv.apple.com/api/uts/v3/movies/{umc}?{params}"))["data"]
    title = (d.get("content") or {}).get("title")
    for p in (d.get("playables") or {}).values():
        for clip in (p.get("itunesMediaApiData") or {}).get("movieClips") or []:
            if clip.get("hlsUrl"):
                return clip["hlsUrl"], title
    bg = ((d.get("content") or {}).get("backgroundVideo") or {}).get("assets") or {}
    return bg.get("hlsUrl"), title


_ATTR = re.compile(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)')


def _attrs(line: str) -> dict:
    return {k: v.strip('"') for k, v in _ATTR.findall(line.split(":", 1)[1])}


def _lines(res: str) -> int:
    try:
        w, h = (int(x) for x in res.split("x"))
    except ValueError:
        return 0
    return max(h, round(w * 9 / 16))  # 16:9-equivalent — scope trailers are cropped


def parse_master(text: str, base: str, max_lines: int, lang: str) -> dict:
    """Pick the best HDR video, best SDR video and best audio from a master
    playlist. Each variant URI appears once per audio group; dedupe by URI."""
    videos: dict[str, dict] = {}
    audios: list[dict] = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("#EXT-X-STREAM-INF") and i + 1 < len(lines):
            a = _attrs(line)
            uri = urllib.parse.urljoin(base, lines[i + 1].strip())
            bw = int(a.get("AVERAGE-BANDWIDTH") or a.get("BANDWIDTH") or 0)
            v = videos.setdefault(uri, {
                "uri": uri, "res": a.get("RESOLUTION", ""),
                "range": a.get("VIDEO-RANGE", "SDR"),
                "codec": (a.get("CODECS", "").split(",") or [""])[0], "bw": bw})
            v["bw"] = min(v["bw"], bw) if v["bw"] else bw  # least audio overhead
        elif line.startswith("#EXT-X-MEDIA") and "TYPE=AUDIO" in line:
            a = _attrs(line)
            if a.get("URI"):
                audios.append({"uri": urllib.parse.urljoin(base, a["URI"]),
                               "group": a.get("GROUP-ID", ""),
                               "lang": a.get("LANGUAGE", ""),
                               "channels": a.get("CHANNELS", "2")})
    fits = [v for v in videos.values() if 0 < _lines(v["res"]) <= max_lines + 40]
    best = lambda vs: max(vs, key=lambda v: (_lines(v["res"]), v["bw"]), default=None)
    hdr = best([v for v in fits if v["range"] in ("PQ", "HLG")])
    sdr = best([v for v in fits if v["range"] == "SDR"])

    want = (lang or "en").split("-")[0].lower()

    def audio_rank(a: dict) -> tuple:
        g = a["group"].lower()
        kind = (3 if ("atmos" in g or "joc" in a["channels"].lower()) else
                2 if "ac3" in g else 1 if "stereo-160" in g else 0)
        return (a["lang"].lower().startswith(want), kind)

    audio = max(audios, key=audio_rank, default=None)
    return {"hdr": hdr, "sdr": sdr, "audio": audio}


async def find(tmdb_id: int | None) -> dict | None:
    """The movie's Apple trailer (variants picked), or None. Cached per process."""
    s = get_settings()
    if not s.apple_trailers or not tmdb_id:
        return None
    hit = _offers.get(tmdb_id)
    if hit and time.time() - hit[0] < _OFFER_TTL:
        return hit[1]
    offer = None
    umc = (await resolve_ids([tmdb_id])).get(tmdb_id)
    if umc:
        for attempt in (0, 1):
            try:
                tok = await _catalog_tokens(refresh=attempt == 1)
                hls, title = await asyncio.to_thread(_trailer_hls_sync, umc, tok)
                if hls:
                    hls = hls.replace("aec=HD", "aec=UHD")  # unlocks the 4K ladder
                    master = await asyncio.to_thread(_get, hls)
                    picked = parse_master(master, hls, s.trailer_max_height,
                                          s.trailer_locale)
                    if picked["sdr"] or picked["hdr"]:
                        offer = {"umc": umc, "hls": hls, "title": title, **picked}
                break
            except (urllib.error.URLError, OSError, ValueError, KeyError):
                continue  # stale tokens → retry once with fresh ones
    _offers[tmdb_id] = (time.time(), offer)
    return offer


# --- Download -----------------------------------------------------------------

def _mux_sync(ffmpeg: str, video: dict, audio: dict | None, out: Path) -> bool:
    part = out.with_name(out.name + ".part.mkv")
    args = [ffmpeg, "-nostdin", "-v", "error", "-y", "-user_agent", _UA_BROWSER,
            "-i", video["uri"]]
    if audio:
        args += ["-user_agent", _UA_BROWSER, "-i", audio["uri"]]
    args += ["-map", "0:v:0"] + (["-map", "1:a:0"] if audio else []) + [
        "-c", "copy", str(part)]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=900)
    except (subprocess.TimeoutExpired, OSError):
        part.unlink(missing_ok=True)
        return False
    if r.returncode != 0 or not part.exists() or part.stat().st_size < 100_000:
        part.unlink(missing_ok=True)
        return False
    part.replace(out)
    return True


async def download(offer: dict, main: Path, sdr_copy: Path) -> dict | None:
    """Fetch the trailer: the main file is HDR when Apple offers it (plus an SDR
    copy for players that can't show HDR), else the best SDR. Returns what was
    written, or None. Writes to temp names and only replaces on success."""
    from .ffmpeg import ffmpeg_path
    ff = ffmpeg_path()
    if not ff:
        return None
    primary = offer["hdr"] or offer["sdr"]
    if not await asyncio.to_thread(_mux_sync, ff, primary, offer["audio"], main):
        return None
    wrote_sdr = False
    if offer["hdr"] and offer["sdr"]:
        wrote_sdr = await asyncio.to_thread(_mux_sync, ff, offer["sdr"], offer["audio"], sdr_copy)
    if not wrote_sdr:
        sdr_copy.unlink(missing_ok=True)
    a = offer["audio"] or {}
    return {
        "source": "apple", "umc": offer["umc"], "title": offer.get("title"),
        "hdr": bool(offer["hdr"]), "video": f'{primary["res"]} {primary["range"]} {primary["codec"]}',
        "sdr_copy": f'{offer["sdr"]["res"]} {offer["sdr"]["codec"]}' if wrote_sdr else None,
        "audio": f'{a.get("group", "none")} ({a.get("channels", "?")}ch {a.get("lang", "")})',
    }
