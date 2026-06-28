"""FastAPI application + Socket.IO mount.

The Socket.IO layer is where scan progress, phone-as-remote control, and
Watch Together will live. For now it just accepts connections.
"""

from __future__ import annotations

from collections import deque
from contextlib import asynccontextmanager
from pathlib import Path

import socketio
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from . import __version__
from .api.movies import router as movies_router
from .api.stream import router as stream_router
from .api.subtitles import router as subtitles_router
from .api.update import router as update_router
from .config import get_settings
from .db import engine
from .ffmpeg import ffmpeg_path, ffprobe_path
from .streaming import startup_cleanup


async def _db_ok() -> bool:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


@asynccontextmanager
async def _lifespan(app: FastAPI):
    # Reap transcodes orphaned by a prior run + trim the cache. NOTE: under the
    # socketio.ASGIApp wrapper this lifespan does not actually fire — nascinema_run.py does
    # the same cleanup at startup. Kept for direct-ASGI / future use.
    startup_cleanup()
    yield


def create_fastapi() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="NASCinema", version=__version__, lifespan=_lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        # We authenticate with bearer tokens (Authorization header), not cookies,
        # so credentials stay off — which keeps "*" origins valid for browsers.
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/api/health")
    async def health() -> dict:
        return {
            "app": "NASCinema",
            "version": __version__,
            "status": "ok",
            "db": await _db_ok(),
            "ffmpeg": bool(ffmpeg_path()),
            "ffprobe": bool(ffprobe_path()),
            "media_dirs": len(settings.media_dir_list),
        }

    app.include_router(movies_router)
    app.include_router(stream_router)
    app.include_router(subtitles_router)
    app.include_router(update_router)

    # Cast receiver debug pipe: the branded receiver POSTs each on-screen debug
    # line here so we can read what happened on the TV without chrome://inspect.
    # Registered before the /cast static mount so it isn't swallowed by it.
    _cast_log: deque[str] = deque(maxlen=200)

    @app.post("/cast/log")
    async def cast_log_post(req: Request) -> dict:
        try:
            data = await req.json()
        except Exception:
            data = {}
        msg = str(data.get("msg", ""))[:500]
        _cast_log.append(msg)
        return {"ok": True}

    @app.get("/cast/log")
    async def cast_log_get() -> dict:
        return {"lines": list(_cast_log)}

    @app.delete("/cast/log")
    async def cast_log_clear() -> dict:
        _cast_log.clear()
        return {"ok": True}

    # The custom Cast receiver (branded TV "now playing" screen). Served here so
    # it lives in one place; an HTTPS reverse proxy (nginx on the NAS) fronts it
    # for Cast, which requires custom receivers over HTTPS.
    cast_dir = Path(__file__).resolve().parents[1] / "cast"
    if cast_dir.is_dir():
        app.mount("/cast", StaticFiles(directory=str(cast_dir)), name="cast")

    # Serve the built Flutter web app (if present) at the root, so the UI is
    # reachable in any browser with no client-side tooling. Mounted last so the
    # /api/* routes above take precedence.
    web_dir = Path(__file__).resolve().parents[2] / "frontend" / "build" / "web"
    if web_dir.is_dir():
        app.mount("/", StaticFiles(directory=str(web_dir), html=True), name="web")

    return app


fastapi_app = create_fastapi()

# Socket.IO server wrapping the FastAPI app as a single ASGI application.
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins=get_settings().cors_origin_list or "*",
)


@sio.event
async def connect(sid, environ, auth):  # noqa: ANN001
    # Auth enforcement comes with the real-time features; accept for now.
    return True


app = socketio.ASGIApp(sio, other_asgi_app=fastapi_app)
