"""On-the-fly HLS sessions (remux or transcode) backed by an ffmpeg subprocess.

One ffmpeg process per file writes HLS segments into a per-file cache dir; the
stream endpoints serve the playlist + segments as they appear. ffmpeg is run via
plain subprocess (not asyncio) because the Windows SelectorEventLoop we need for
psycopg can't spawn asyncio subprocesses.
"""

from __future__ import annotations

import shutil
import subprocess
import threading
import time
from pathlib import Path

from .config import get_settings
from .ffmpeg import ffmpeg_path

_sessions: dict[int, "Session"] = {}
_lock = threading.Lock()


class Session:
    def __init__(self, file_id: int, out_dir: Path, proc: subprocess.Popen, mode: str):
        self.file_id = file_id
        self.dir = out_dir
        self.proc = proc
        self.mode = mode
        self.last_access = time.time()

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    @property
    def playlist(self) -> Path:
        return self.dir / "master.m3u8"


def _cache_root() -> Path:
    root = (Path(get_settings().data_dir) / "hls").resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def _build_cmd(src: str, decision: dict, out_dir: Path) -> list[str]:
    ff = ffmpeg_path()
    args = [ff, "-hide_banner", "-loglevel", "error", "-y", "-i", src]

    if decision["video"] == "copy":
        args += ["-c:v", "copy"]
    else:
        args += [
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            # Cap the web stream at 1080p — far lighter than re-encoding 4K.
            "-vf", "scale='min(1920,iw)':-2:flags=bicubic", "-pix_fmt", "yuv420p",
        ]

    if decision["audio"] == "copy":
        args += ["-c:a", "copy"]
    else:
        args += ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]

    args += [
        "-f", "hls",
        "-hls_time", "4",
        # 'event' = a growing VOD playlist the viewer watches from the start
        # (vs. a live sliding window, which makes hls.js sit at the live edge).
        "-hls_playlist_type", "event",
        "-hls_list_size", "0",
        "-hls_flags", "independent_segments",
        "-hls_segment_filename", str(out_dir / "seg_%05d.ts"),
        str(out_dir / "master.m3u8"),
    ]
    return args


def get_or_start(file_id: int, src_path: str, decision: dict) -> Session:
    with _lock:
        existing = _sessions.get(file_id)
        if existing and existing.alive:
            existing.last_access = time.time()
            return existing

        out_dir = _cache_root() / str(file_id)
        if out_dir.exists():
            shutil.rmtree(out_dir, ignore_errors=True)
        out_dir.mkdir(parents=True, exist_ok=True)

        log = open(out_dir / "ffmpeg.log", "w")  # noqa: SIM115 (held by ffmpeg)
        proc = subprocess.Popen(
            _build_cmd(src_path, decision, out_dir),
            stdout=subprocess.DEVNULL,
            stderr=log,
        )
        session = Session(file_id, out_dir, proc, decision["mode"])
        _sessions[file_id] = session
        return session


def session_dir(file_id: int) -> Path | None:
    s = _sessions.get(file_id)
    if s:
        s.last_access = time.time()
        return s.dir
    return None
