"""FastAPI application + Socket.IO mount.

The Socket.IO layer is where scan progress, phone-as-remote control, and
Watch Together will live. For now it just accepts connections.
"""

from __future__ import annotations

import socketio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from . import __version__
from .api.movies import router as movies_router
from .config import get_settings
from .db import engine
from .ffmpeg import ffmpeg_path, ffprobe_path


async def _db_ok() -> bool:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


def create_fastapi() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="NASCinema", version=__version__)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
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
