"""Dev/prod entrypoint. `python run.py` to serve; `--scan` reserved for Phase 1."""

from __future__ import annotations

import argparse

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

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=args.reload,
    )


if __name__ == "__main__":
    main()
