"""On-the-fly HLS sessions (remux or transcode) backed by an ffmpeg subprocess.

For transcodes we force a keyframe every SEG_SECONDS so segments are uniform,
then write a full VOD playlist up front from the known duration — so the player
shows the real total runtime and a proper timeline, and segments are served as
ffmpeg produces them (it stays ahead of sequential playback). Remux/copy can't
force keyframes, so it falls back to a growing event playlist.

ffmpeg is run via plain subprocess (not asyncio) because the Windows
SelectorEventLoop we need for psycopg can't spawn asyncio subprocesses.
"""

from __future__ import annotations

import shutil
import subprocess
import threading
import time
from pathlib import Path

from .config import get_settings
from .ffmpeg import ffmpeg_path

SEG_SECONDS = 4

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


def _write_vod_playlist(out_dir: Path, duration: float) -> None:
    """Pre-write a full VOD playlist of uniform SEG_SECONDS segments so the
    player knows the real total runtime and can seek."""
    full = int(duration // SEG_SECONDS)
    remainder = duration - full * SEG_SECONDS
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        f"#EXT-X-TARGETDURATION:{SEG_SECONDS + 1}",
        "#EXT-X-MEDIA-SEQUENCE:0",
        "#EXT-X-PLAYLIST-TYPE:VOD",
    ]
    for i in range(full):
        lines.append(f"#EXTINF:{float(SEG_SECONDS):.3f},")
        lines.append(f"seg_{i:05d}.ts")
    if remainder > 0.1:
        lines.append(f"#EXTINF:{remainder:.3f},")
        lines.append(f"seg_{full:05d}.ts")
    lines.append("#EXT-X-ENDLIST")
    (out_dir / "master.m3u8").write_text("\n".join(lines) + "\n")


def _build_cmd(
    src: str, decision: dict, out_dir: Path, playlist_name: str, force_kf: bool
) -> list[str]:
    ff = ffmpeg_path()
    args = [ff, "-hide_banner", "-loglevel", "error", "-y", "-i", src]

    if decision["video"] == "copy":
        args += ["-c:v", "copy"]
    else:
        args += [
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            "-vf", "scale='min(1920,iw)':-2:flags=bicubic", "-pix_fmt", "yuv420p",
        ]
        if force_kf:
            args += ["-force_key_frames", f"expr:gte(t,n_forced*{SEG_SECONDS})"]

    if decision["audio"] == "copy":
        args += ["-c:a", "copy"]
    else:
        args += ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]

    args += [
        "-f", "hls",
        "-hls_time", str(SEG_SECONDS),
        "-hls_playlist_type", "event",
        "-hls_list_size", "0",
        # temp_file => a present segment is fully written (atomic rename).
        "-hls_flags", "independent_segments+temp_file",
        "-hls_segment_filename", str(out_dir / "seg_%05d.ts"),
        str(out_dir / playlist_name),
    ]
    return args


def get_or_start(
    file_id: int, src_path: str, decision: dict, duration: float | None
) -> Session:
    with _lock:
        existing = _sessions.get(file_id)
        if existing and existing.alive:
            existing.last_access = time.time()
            return existing

        out_dir = _cache_root() / str(file_id)
        if out_dir.exists():
            shutil.rmtree(out_dir, ignore_errors=True)
        out_dir.mkdir(parents=True, exist_ok=True)

        # Transcode -> uniform keyframes + our own full VOD playlist (real
        # runtime). Copy/remux -> let ffmpeg write the growing playlist.
        use_vod = decision["video"] == "transcode" and bool(duration)
        playlist_name = "ff.m3u8" if use_vod else "master.m3u8"

        log = open(out_dir / "ffmpeg.log", "w")  # noqa: SIM115 (held by ffmpeg)
        proc = subprocess.Popen(
            _build_cmd(src_path, decision, out_dir, playlist_name, force_kf=use_vod),
            stdout=subprocess.DEVNULL,
            stderr=log,
        )
        if use_vod:
            _write_vod_playlist(out_dir, duration)

        session = Session(file_id, out_dir, proc, decision["mode"])
        _sessions[file_id] = session
        return session


def session_dir(file_id: int) -> Path | None:
    s = _sessions.get(file_id)
    if s:
        s.last_access = time.time()
        return s.dir
    return None
