"""Dev/prod entrypoint. `python run.py` to serve; `--scan` reserved for Phase 1.

Windows note: psycopg's async driver requires a SelectorEventLoop, but uvicorn
picks ProactorEventLoop for single-process serving on Windows. So on win32 we
drive uvicorn on a SelectorEventLoop ourselves. (`--reload` runs uvicorn in its
subprocess mode, which already uses a SelectorEventLoop.)
"""

from __future__ import annotations

import argparse
import asyncio
import sys

import uvicorn

from app.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description="NASCinema backend")
    parser.add_argument(
        "--scan",
        action="store_true",
        help="Scan the media library on startup (Phase 1 — not yet implemented).",
    )
    parser.add_argument("--reload", action="store_true", help="Auto-reload (dev).")
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Scan at most N new files (smoke test).",
    )
    parser.add_argument(
        "--fingerprint",
        action="store_true",
        help="Backfill Chromaprint fingerprints for extras (Extras DB groundwork).",
    )
    args = parser.parse_args()

    settings = get_settings()

    if args.fingerprint:
        from app.scanner import fingerprint_extras

        print("[NASCinema] fingerprinting extras (Chromaprint)...")
        stats = asyncio.run(fingerprint_extras())
        print(f"[NASCinema] fingerprint complete: {stats}")
        return

    if args.scan:
        from app.scanner import scan

        print("[NASCinema] scanning library...")
        stats = asyncio.run(scan(limit=args.limit))
        print(f"[NASCinema] scan complete: {stats}")
        return

    target = "app.main:app"

    if args.reload:
        # Subprocess mode uses a SelectorEventLoop on Windows already.
        uvicorn.run(target, host=settings.host, port=settings.port, reload=True)
    elif sys.platform == "win32":
        config = uvicorn.Config(target, host=settings.host, port=settings.port, loop="none")
        server = uvicorn.Server(config)

        async def _serve() -> None:
            # socketio's ASGIApp doesn't forward ASGI lifespan to the wrapped
            # FastAPI app, so the FastAPI lifespan never runs under this
            # entrypoint — run startup work here: reap transcodes orphaned by a
            # restart + trim the cache.
            from app.streaming import startup_cleanup

            startup_cleanup()
            await server.serve()

        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(_serve())
    else:
        uvicorn.run(target, host=settings.host, port=settings.port)


if __name__ == "__main__":
    main()
