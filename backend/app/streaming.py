"""On-the-fly HLS sessions (remux or transcode) with smart seek.

A transcode runs sequentially from a start segment and stays ahead of playback.
When the player asks for a segment far beyond the current head — i.e. a seek —
we restart ffmpeg *at that point* (`-ss`) with `-start_number` so the wanted
segment is produced in seconds instead of waiting for the whole gap to encode.
Forced 4s keyframes + a pre-written VOD playlist give a real timeline. Copy/
remux can't force keyframes, so it stays a simple sequential event playlist.

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
# Within this many segments of the transcode head -> sequential, just wait.
# Beyond it -> a seek, so restart the transcode there.
WAIT_AHEAD = 12

_sessions: dict[int, "Session"] = {}
_lock = threading.Lock()


class Session:
    def __init__(self, file_id, out_dir, src, decision, duration):
        self.file_id = file_id
        self.dir = out_dir
        self.src = src
        self.decision = decision
        self.duration = duration
        self.vod = decision["video"] == "transcode" and bool(duration)
        self.proc: subprocess.Popen | None = None
        self.start_num = 0
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


def reset_cache() -> None:
    """Wipe the HLS cache at startup. Stale segments left by a previous run
    (e.g. an ffmpeg orphaned by a restart) would otherwise poison the head
    count and break seek decisions, so we clear them before serving."""
    _sessions.clear()
    root = (Path(get_settings().data_dir) / "hls").resolve()
    if root.exists():
        shutil.rmtree(root, ignore_errors=True)


def _write_vod_playlist(out_dir: Path, duration: float) -> None:
    full = int(duration // SEG_SECONDS)
    remainder = duration - full * SEG_SECONDS
    lines = [
        "#EXTM3U", "#EXT-X-VERSION:3",
        f"#EXT-X-TARGETDURATION:{SEG_SECONDS + 1}",
        "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD",
    ]
    for i in range(full):
        lines.append(f"#EXTINF:{float(SEG_SECONDS):.3f},")
        lines.append(f"seg_{i:05d}.ts")
    if remainder > 0.1:
        lines.append(f"#EXTINF:{remainder:.3f},")
        lines.append(f"seg_{full:05d}.ts")
    lines.append("#EXT-X-ENDLIST")
    (out_dir / "master.m3u8").write_text("\n".join(lines) + "\n")


def _head(out_dir: Path, default: int) -> int:
    best = default
    try:
        for p in out_dir.glob("seg_*.ts"):
            try:
                n = int(p.stem.split("_")[1])
                best = max(best, n)
            except (ValueError, IndexError):
                pass
    except OSError:
        pass
    return best


def _build_cmd(sess: "Session", start_num: int) -> list[str]:
    ff = ffmpeg_path()
    d = sess.decision
    args = [ff, "-hide_banner", "-loglevel", "error", "-y"]
    if start_num > 0:
        args += ["-ss", str(start_num * SEG_SECONDS)]  # fast input seek
    args += ["-i", sess.src]

    if d["video"] == "copy":
        args += ["-c:v", "copy"]
    else:
        args += [
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            "-vf", "scale='min(1920,iw)':-2:flags=bicubic", "-pix_fmt", "yuv420p",
            "-force_key_frames", f"expr:gte(t,n_forced*{SEG_SECONDS})",
        ]

    if d["audio"] == "copy":
        args += ["-c:a", "copy"]
    else:
        args += ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]

    playlist = "ff.m3u8" if sess.vod else "master.m3u8"
    args += [
        "-f", "hls", "-hls_time", str(SEG_SECONDS),
        "-hls_playlist_type", "event", "-hls_list_size", "0",
        "-hls_flags", "independent_segments+temp_file",
        "-start_number", str(start_num),
        "-hls_segment_filename", str(sess.dir / "seg_%05d.ts"),
        str(sess.dir / playlist),
    ]
    return args


def _spawn(sess: "Session", start_num: int) -> None:
    if sess.proc and sess.alive:
        try:
            sess.proc.terminate()
        except Exception:
            pass
    log = open(sess.dir / "ffmpeg.log", "w")  # noqa: SIM115 (held by ffmpeg)
    sess.proc = subprocess.Popen(
        _build_cmd(sess, start_num), stdout=subprocess.DEVNULL, stderr=log
    )
    sess.start_num = start_num


def get_or_start(file_id, src_path, decision, duration) -> "Session":
    with _lock:
        existing = _sessions.get(file_id)
        if existing and existing.alive:
            existing.last_access = time.time()
            return existing

        out_dir = _cache_root() / str(file_id)
        if out_dir.exists():
            shutil.rmtree(out_dir, ignore_errors=True)
        out_dir.mkdir(parents=True, exist_ok=True)

        sess = Session(file_id, out_dir, src_path, decision, duration)
        if sess.vod:
            _write_vod_playlist(out_dir, duration)
        _spawn(sess, 0)
        _sessions[file_id] = sess
        return sess


def ensure_segment(file_id: int, seg_index: int) -> Path | None:
    """Return the path for a segment, restarting the transcode at the seek
    point if it's far beyond what's been produced. The caller waits for it."""
    sess = _sessions.get(file_id)
    if sess is None:
        return None
    sess.last_access = time.time()
    path = sess.dir / f"seg_{seg_index:05d}.ts"
    if path.exists() and path.stat().st_size > 0:
        return path
    if not sess.vod:
        return path  # copy/remux: sequential, the caller just waits

    head = _head(sess.dir, sess.start_num)
    seek = (not sess.alive) or seg_index < sess.start_num or seg_index > head + WAIT_AHEAD
    if seek:
        with _lock:
            if not (path.exists() and path.stat().st_size > 0):
                _spawn(sess, seg_index)
    return path
