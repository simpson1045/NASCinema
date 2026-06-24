"""Locate ffmpeg/ffprobe without hardcoding a path.

Resolution order: explicit config override -> PATH -> common install dirs.
The common dirs are *search candidates*, not requirements — any of them may be
absent, and an operator can always point NASCINEMA_FFMPEG / _FFPROBE elsewhere.
"""

from __future__ import annotations

import os
import shutil
from functools import lru_cache
from pathlib import Path

from .config import get_settings

# Best-effort search locations across typical Windows/Linux setups.
_COMMON_DIRS = [
    r"C:\ytdl",
    r"C:\ffmpeg\bin",
    r"C:\Program Files\ffmpeg\bin",
    os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Links"),
    "/usr/bin",
    "/usr/local/bin",
    "/opt/homebrew/bin",
]


def _resolve(name: str, override: str) -> str | None:
    if override and Path(override).exists():
        return override
    found = shutil.which(name)
    if found:
        return found
    exe = name + (".exe" if os.name == "nt" else "")
    for d in _COMMON_DIRS:
        if not d:
            continue
        cand = Path(d) / exe
        if cand.exists():
            return str(cand)
    return None


@lru_cache
def ffmpeg_path() -> str | None:
    return _resolve("ffmpeg", get_settings().ffmpeg)


@lru_cache
def ffprobe_path() -> str | None:
    return _resolve("ffprobe", get_settings().ffprobe)
