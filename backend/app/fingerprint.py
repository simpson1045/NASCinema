"""Chromaprint (fpcalc) audio fingerprinting for the crowdsourced Extras DB.

A fingerprint is a stable, re-encode-robust signature of an extra's audio, so
the same featurette across different rips matches. Opt-in via
NASCINEMA_CONTRIBUTE_EXTRAS. Submission to the central service is a later phase
— for now we just compute and store fingerprints locally. See EXTRAS_DB.md.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path

from .config import get_settings

_COMMON_DIRS = [
    r"C:\chromaprint",
    r"C:\Program Files\Chromaprint",
    r"C:\ytdl",
    "/usr/bin",
    "/usr/local/bin",
    "/opt/homebrew/bin",
]


@lru_cache
def fpcalc_path() -> str | None:
    override = get_settings().fpcalc
    if override and Path(override).exists():
        return override
    found = shutil.which("fpcalc")
    if found:
        return found
    exe = "fpcalc.exe" if os.name == "nt" else "fpcalc"
    for d in _COMMON_DIRS:
        cand = Path(d) / exe
        if cand.exists():
            return str(cand)
    return None


async def fingerprint_file(path: str, length: int = 120) -> str | None:
    """Return the Chromaprint fingerprint of the first `length` seconds of audio,
    or None if fpcalc is unavailable or the file can't be decoded."""
    exe = fpcalc_path()
    if not exe:
        return None

    args = [exe, "-json", "-length", str(length), path]

    def _run() -> subprocess.CompletedProcess:
        return subprocess.run(args, capture_output=True, text=True, timeout=120)

    try:
        proc = await asyncio.to_thread(_run)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    return data.get("fingerprint") or None
