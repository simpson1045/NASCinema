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
    args = parser.parse_args()

    settings = get_settings()

    if args.scan:
        print("[NASCinema] --scan is reserved for Phase 1 (library scanner). Skipping.")

    target = "app.main:app"

    if args.reload:
        # Subprocess mode uses a SelectorEventLoop on Windows already.
        uvicorn.run(target, host=settings.host, port=settings.port, reload=True)
    elif sys.platform == "win32":
        config = uvicorn.Config(target, host=settings.host, port=settings.port, loop="none")
        server = uvicorn.Server(config)
        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(server.serve())
    else:
        uvicorn.run(target, host=settings.host, port=settings.port)


if __name__ == "__main__":
    main()
