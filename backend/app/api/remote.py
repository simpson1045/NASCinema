"""Remote control — drive a renderer (the NASCinema app on a theater PC) from
outside: "play Jurassic Park", "resume Whose Line", pause, seek, tracks.

How it fits together:
  * The renderer app connects to the Socket.IO server, says `player_hello`
    with its name ("ELKO"), and sends `player_status` every few seconds and on
    every change (what's playing, position, tracks, audio out format).
  * The REST endpoints here resolve names to ids on the server (fuzzy title
    match, Theatrical-first versions, the show's next-up episode) and hand the
    renderer a concrete command over the socket, then WAIT for its answer —
    so the caller hears "playing" or "NOT STARTED: <why>", never a command
    left sitting in a queue to fire hours later. A renderer that isn't
    connected gets nothing; the call fails right away.
  * Everything under /api/remote needs NASCINEMA_REMOTE_TOKEN (Bearer or
    X-Remote-Token). The API is reachable from the internet, and this one can
    drive the TV. No token configured = remote control off (503).
"""

from __future__ import annotations

import hmac
import re
import time
from difflib import SequenceMatcher

import socketio
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..config import get_settings
from ..db import get_session
from ..models import Episode, MediaFile, Movie, Show, WatchProgress
from ..tracks import quality_label, version_label
from .movies import _features
from .shows import _episode, _load_show, _next_up, _order, _progress, _watched, continue_shows


def _auth(authorization: str | None = Header(None),
          x_remote_token: str | None = Header(None)) -> None:
    token = get_settings().remote_token.strip()
    if not token:
        raise HTTPException(503, "remote control is off (set NASCINEMA_REMOTE_TOKEN)")
    given = (x_remote_token or "").strip() or \
        (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(given.encode(), token.encode()):
        raise HTTPException(401, "bad remote token")


router = APIRouter(prefix="/api/remote", tags=["remote"], dependencies=[Depends(_auth)])

# ── Player registry (filled by the Socket.IO handlers) ──────────────────────

_sio: socketio.AsyncServer | None = None
_players: dict[str, dict] = {}  # lower-case name -> {name, sid, version, since, status, status_at}


def attach(sio: socketio.AsyncServer) -> None:
    """Register the renderer-side socket events. Called once from main.py."""
    global _sio
    _sio = sio

    @sio.on("player_hello")
    async def player_hello(sid, data):  # noqa: ANN001
        name = str((data or {}).get("name") or "").strip()[:64]
        if not name:
            return {"ok": False, "error": "name required"}
        _players[name.lower()] = {
            "name": name, "sid": sid, "version": (data or {}).get("version"),
            "since": time.time(), "status": {}, "status_at": None,
        }
        return {"ok": True}

    @sio.on("player_status")
    async def player_status(sid, data):  # noqa: ANN001
        for p in _players.values():
            if p["sid"] == sid:
                p["status"] = data if isinstance(data, dict) else {}
                p["status_at"] = time.time()

    @sio.event
    async def disconnect(sid):  # noqa: ANN001
        for key in [k for k, p in _players.items() if p["sid"] == sid]:
            del _players[key]


def _player(name: str) -> dict:
    key = name.strip().lower()
    p = _players.get(key)
    if not p and key:
        # "ELKO" finds "DESKTOP-ELKO" (the app defaults to the PC's hostname)
        # when it's the only connected player with that in its name.
        near = [v for k, v in _players.items() if key in k]
        p = near[0] if len(near) == 1 else None
    if not p:
        raise HTTPException(409, f"{name} isn't connected — is NASCinema open on it?")
    return p


def _public(p: dict) -> dict:
    age = round(time.time() - p["status_at"], 1) if p["status_at"] else None
    return {"name": p["name"], "connected": True, "version": p["version"],
            "connected_for": round(time.time() - p["since"]), "status_age": age,
            "status": p["status"]}


async def _send(player: str, action: str, timeout: float = 15, **args) -> dict:
    """Hand the renderer one command and wait for its reply."""
    p = _player(player)
    if _sio is None:
        raise HTTPException(503, "socket server not attached")
    try:
        reply = await _sio.call("remote_command", {"action": action, **args},
                                to=p["sid"], timeout=timeout)
    except socketio.exceptions.TimeoutError:
        raise HTTPException(504, f"{p['name']} didn't answer '{action}' within {timeout:.0f}s")
    return reply if isinstance(reply, dict) else {"ok": False, "error": "no reply"}


def _busy(player: str) -> str | None:
    """What's on screen right now, if anything (the don't-clobber guard)."""
    st = _player(player)["status"]
    if st.get("state") in ("playing", "paused"):
        return st.get("title") or "something"
    return None


# ── Name matching ───────────────────────────────────────────────────────────

_YEAR = re.compile(r"\(?\b((?:19|20)\d{2})\)?\s*$")


def _norm(s: str) -> str:
    s = (s or "").lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"^the ", "", s)


def _score(query: str, title: str, year: int | None) -> float:
    """1.0 = exact title. A trailing year in the query ("Dune 1984") picks
    between remakes."""
    q = query.strip()
    qyear = None
    m = _YEAR.search(q)
    if m and _norm(q[:m.start()]):
        qyear, q = int(m.group(1)), q[:m.start()]
    qn, tn = _norm(q), _norm(title)
    if not qn or not tn:
        return 0.0
    if qn == tn:
        s = 1.0
    elif tn.startswith(qn) or f" {qn} " in f" {tn} ":
        s = 0.75 + 0.2 * len(qn) / len(tn)  # "jurassic park" in "jurassic park iii"
    else:
        s = SequenceMatcher(None, qn, tn).ratio() * 0.9
    if qyear is not None and year is not None:
        s += 0.1 if qyear == year else -0.25
    return s


def _rank(query: str, items: list, title, year) -> list[tuple[float, object]]:
    scored = [(_score(query, title(i), year(i)), i) for i in items]
    # Ties: the closer-length title, then the older film ("Star Wars" → 1977).
    scored.sort(key=lambda t: (-round(t[0], 3), len(title(t[1])), year(t[1]) or 9999))
    # 0.7: typos still land ("jurasic park"), lookalikes don't ("whose line"
    # → Home Alone scored 0.63).
    return [t for t in scored if t[0] >= 0.7]


async def _movies(session: AsyncSession) -> list[Movie]:
    return list((await session.scalars(
        select(Movie).options(selectinload(Movie.files).selectinload(MediaFile.streams))
    )).all())


def _movie_brief(m: Movie) -> dict:
    return {"id": m.id, "title": m.title, "year": m.year, "kind": "movie",
            "versions": len(_features(m.files))}


def _show_brief(s: Show) -> dict:
    return {"id": s.id, "title": s.title, "year": s.year, "kind": "show"}


def _versions(m: Movie) -> list[dict]:
    return [{"file_id": f.id, "label": version_label(f), "quality": quality_label(f),
             "duration": f.duration} for f in _features(m.files)]


async def _find_movie(session: AsyncSession, query: str | None, movie_id: int | None) -> tuple[Movie, list[dict]]:
    movies = await _movies(session)
    if movie_id:
        m = next((m for m in movies if m.id == movie_id), None)
        if not m:
            raise HTTPException(404, f"no movie with id {movie_id}")
        return m, []
    if not query:
        raise HTTPException(422, "query or movie_id required")
    hits = _rank(query, [m for m in movies if _features(m.files)],
                 lambda m: m.title, lambda m: m.year)
    if not hits:
        raise HTTPException(404, f"no movie matching '{query}'")
    return hits[0][1], [_movie_brief(m) for _, m in hits[1:6]]


def _pick_version(m: Movie, version: str | None, file_id: int | None) -> MediaFile | None:
    feats = _features(m.files)
    if file_id:
        f = next((f for f in feats if f.id == file_id), None)
        if not f:
            raise HTTPException(404, f"file {file_id} isn't a version of {m.title}")
        return f
    if version:
        want = _norm(version)
        f = next((f for f in feats if want in _norm(version_label(f))), None) or \
            next((f for f in feats if want in _norm(quality_label(f))), None)
        if not f:
            labels = ", ".join(version_label(f) for f in feats)
            raise HTTPException(404, f"{m.title} has no '{version}' version (has: {labels})")
        return f
    return None  # the renderer's own pick (saved choice, else Theatrical-first)


async def _find_show(session: AsyncSession, name: str | None, show_id: int | None) -> tuple[Show, list[dict]]:
    if show_id:
        s = await _load_show(session, show_id)
        if not s:
            raise HTTPException(404, f"no show with id {show_id}")
        return s, []
    if not name:
        raise HTTPException(422, "name or show_id required")
    shows = list((await session.scalars(select(Show))).all())
    hits = _rank(name, shows, lambda s: s.title, lambda s: s.year)
    if not hits:
        raise HTTPException(404, f"no show matching '{name}'")
    return await _load_show(session, hits[0][1].id), [_show_brief(s) for _, s in hits[1:6]]


def _ep_brief(e: dict) -> dict:
    return {"episode_id": e["id"], "season": e["season_number"], "episode": e["episode_number"],
            "title": e["title"], "position": round(e["position"]), "duration": round(e["duration"] or 0),
            "watched": e["watched"]}


# ── Players + playback ──────────────────────────────────────────────────────

@router.get("/players")
async def players() -> dict:
    return {"players": [_public(p) for p in _players.values()]}


@router.get("/players/{player}")
async def player_status(player: str) -> dict:
    return _public(_player(player))


class PlayReq(BaseModel):
    query: str | None = None       # "Jurassic Park", "Dune 1984"
    movie_id: int | None = None
    version: str | None = None     # "theatrical", "4K77", "special edition"
    file_id: int | None = None     # an exact version
    from_start: bool = False
    replace: bool = False          # allow stopping what's playing


@router.post("/players/{player}/play")
async def play_movie(player: str, req: PlayReq, session: AsyncSession = Depends(get_session)) -> dict:
    busy = _busy(player)
    if busy and not req.replace:
        raise HTTPException(409, f"NOT STARTED: '{busy}' is playing — pass replace=true to stop it")
    m, others = await _find_movie(session, req.query, req.movie_id)
    f = _pick_version(m, req.version, req.file_id)
    reply = await _send(player, "play_movie", timeout=45, movie_id=m.id,
                        file_id=f.id if f else None, from_start=req.from_start)
    return {**reply, "movie": _movie_brief(m), "versions": _versions(m),
            "version": version_label(f) if f else None, "other_matches": others}


class ShowReq(BaseModel):
    name: str | None = None
    show_id: int | None = None
    season: int | None = None      # with episode: that exact episode
    episode: int | None = None
    from_start: bool = False
    replace: bool = False


@router.post("/players/{player}/show")
async def play_show(player: str, req: ShowReq, session: AsyncSession = Depends(get_session)) -> dict:
    """Resume a show (the in-progress episode, else the next unwatched — the
    same pick as the show page), or play an exact SxEy."""
    busy = _busy(player)
    if busy and not req.replace:
        raise HTTPException(409, f"NOT STARTED: '{busy}' is playing — pass replace=true to stop it")
    show, others = await _find_show(session, req.name, req.show_id)
    eps = sorted(show.episodes, key=_order)
    prog = await _progress(session, [f.id for e in eps for f in e.files])
    rows = [_episode(e, prog) for e in eps]
    if req.season is not None and req.episode is not None:
        ep = next((e for e in rows if e["season_number"] == req.season and (
            e["episode_number"] == req.episode or
            (e["episode_end"] and e["episode_number"] <= req.episode <= e["episode_end"]))), None)
        if not ep:
            raise HTTPException(404, f"{show.title} has no S{req.season}E{req.episode}")
    else:
        ep = _next_up(rows)
        if not ep:
            raise HTTPException(404, f"everything in {show.title} is watched — ask for an exact episode")
    if not ep["files"]:
        raise HTTPException(404, "that episode has no playable file")
    reply = await _send(player, "play_episode", timeout=45, show_id=show.id,
                        episode_id=ep["id"], from_start=req.from_start)
    return {**reply, "show": _show_brief(show), "episode": _ep_brief(ep), "other_matches": others}


class CommandReq(BaseModel):
    """pause | resume | toggle | stop | seek {seconds, relative} | tracks |
    set_track {type: audio|sub|video, id ('no' = subs off)} |
    version {version | file_id, same_spot} | sleep {minutes | after_current, cancel} |
    sub_delay {seconds} | reload_audio"""
    action: str
    seconds: float | None = None
    relative: bool = False
    type: str | None = None
    id: str | int | None = None
    version: str | None = None
    file_id: int | None = None
    same_spot: bool = False
    minutes: float | None = None
    after_current: bool = False
    cancel: bool = False


_ACTIONS = {"pause", "resume", "toggle", "stop", "seek", "tracks", "set_track",
            "version", "sleep", "sub_delay", "reload_audio"}


@router.post("/players/{player}/command")
async def command(player: str, req: CommandReq) -> dict:
    action = req.action.strip().lower()
    if action not in _ACTIONS:
        raise HTTPException(422, f"unknown action '{action}' ({' | '.join(sorted(_ACTIONS))})")
    args = req.model_dump(exclude={"action"}, exclude_none=True)
    return await _send(player, action, timeout=30 if action == "version" else 15, **args)


# ── Library lookups (no renderer needed) ────────────────────────────────────

@router.get("/search")
async def search(q: str, session: AsyncSession = Depends(get_session)) -> dict:
    movies = [m for m in await _movies(session) if _features(m.files)]
    shows = list((await session.scalars(select(Show))).all())
    mh = _rank(q, movies, lambda m: m.title, lambda m: m.year)[:8]
    sh = _rank(q, shows, lambda s: s.title, lambda s: s.year)[:5]
    return {"movies": [{**_movie_brief(m), "score": round(s, 2)} for s, m in mh],
            "shows": [{**_show_brief(x), "score": round(s, 2)} for s, x in sh]}


@router.get("/versions")
async def versions(query: str | None = None, movie_id: int | None = None,
                   session: AsyncSession = Depends(get_session)) -> dict:
    """A movie's versions (separate files) in play order. In-file video/audio/
    subtitle streams of what's playing come from the `tracks` command."""
    m, others = await _find_movie(session, query, movie_id)
    return {"movie": _movie_brief(m), "versions": _versions(m), "other_matches": others}


@router.get("/continue")
async def continue_watching(session: AsyncSession = Depends(get_session)) -> dict:
    rows = (await session.execute(
        select(WatchProgress, MediaFile)
        .join(MediaFile, WatchProgress.media_file_id == MediaFile.id)
        .where(MediaFile.kind == "feature", MediaFile.movie_id.is_not(None))
        .order_by(WatchProgress.updated_at.desc()))).all()
    movies, seen = [], set()
    for wp, mf in rows:
        if mf.movie_id in seen or wp.position_seconds < 30 or _watched(wp.position_seconds, mf.duration or 0):
            continue
        seen.add(mf.movie_id)
        m = await session.get(Movie, mf.movie_id)
        if m:
            movies.append({"id": m.id, "title": m.title, "year": m.year,
                           "version": mf.edition or None,
                           "position": round(wp.position_seconds), "duration": round(mf.duration or 0)})
        if len(movies) >= 10:
            break
    shows = (await continue_shows(session))["items"]
    return {"movies": movies,
            "shows": [{**_show_brief_dict(i["show"]), "next": _ep_brief(i["episode"])} for i in shows[:10]]}


def _show_brief_dict(s: dict) -> dict:
    return {"id": s["id"], "title": s["title"], "year": s["year"], "kind": "show"}


@router.get("/recent")
async def recent(limit: int = 15, session: AsyncSession = Depends(get_session)) -> dict:
    movies = (await session.scalars(
        select(Movie).options(selectinload(Movie.files))
        .order_by(Movie.added_at.desc()).limit(limit * 2))).all()
    shows = (await session.scalars(select(Show).order_by(Show.added_at.desc()).limit(limit))).all()
    return {"movies": [{**_movie_brief(m), "added_at": m.added_at.isoformat() if m.added_at else None}
                       for m in movies if _features(m.files)][:limit],
            "shows": [{**_show_brief(s), "added_at": s.added_at.isoformat() if s.added_at else None}
                      for s in shows]}


class WatchedReq(BaseModel):
    query: str | None = None       # a movie title …
    movie_id: int | None = None
    show: str | None = None        # … or a show + season (+ episode)
    show_id: int | None = None
    season: int | None = None
    episode: int | None = None
    watched: bool = True


@router.post("/watched")
async def mark_watched(req: WatchedReq, session: AsyncSession = Depends(get_session)) -> dict:
    """Mark a movie, an episode, or a whole season watched (or unwatched)."""
    if req.show or req.show_id:
        show, _ = await _find_show(session, req.show, req.show_id)
        eps = [e for e in show.episodes
               if (req.season is None or e.season_number == req.season)
               and (req.episode is None or e.episode_number == req.episode)]
        if not eps:
            raise HTTPException(404, "no episodes match")
        files = [f for e in eps for f in e.files]
        what = f"{show.title}" + (f" S{req.season}" if req.season is not None else "") + \
            (f"E{req.episode}" if req.episode is not None else "")
    else:
        m, _ = await _find_movie(session, req.query, req.movie_id)
        files, what = _features(m.files), m.title
    prog = await _progress(session, [f.id for f in files])
    for f in files:
        row = prog.get(f.id)
        if row is None:
            row = WatchProgress(media_file_id=f.id)
            session.add(row)
        row.position_seconds = float(f.duration or 0) if req.watched else 0.0
    await session.commit()
    return {"ok": True, "marked": what, "watched": req.watched, "files": len(files)}
