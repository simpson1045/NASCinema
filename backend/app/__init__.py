"""NASCinema backend — the video sibling of NASRadio.

Versioning is earned: this stays at 0.0.0 (pre-v1.0, nothing shipped) until a
real feature lands. See the README "Design principles".
"""

import asyncio
import sys

# psycopg3's async driver cannot run on Windows' default ProactorEventLoop; it
# requires a SelectorEventLoop. Set the policy at import time so every entry
# point (uvicorn, Alembic, the CLI) gets a compatible loop before one is built.
# NOTE: SelectorEventLoop has no asyncio subprocess support on Windows, so
# ffmpeg/ffprobe must be driven via threads (asyncio.to_thread), not
# asyncio.create_subprocess_exec. (Relevant from Phase 1 onward.)
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

__version__ = "0.2.2"
