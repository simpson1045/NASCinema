"""On-the-fly HLS sessions (remux or transcode) with smart seek + a persistent
transcode cache.

Segments are written to ``<data_dir>/hls/<file_id>/`` and kept across sessions,
so a rewatch — or seeking back into something you already played — is served
straight from disk with no re-encode. A fresh open resumes the transcode at the
first *gap* (skipping cached segments).

Seek logic keys off the active transcode's **contiguous frontier** (the run of
segments from where ffmpeg actually started), not the highest file on disk —
otherwise a cache with gaps, or an ffmpeg orphaned by a restart, would make a
needed segment look "already past the head" and never get produced.

ffmpeg runs via plain subprocess (not asyncio): the Windows SelectorEventLoop we
need for psycopg can't spawn asyncio subprocesses. We record spawned PIDs so a
later run can reap transcodes orphaned by a restart (keeping their segments).
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from functools import lru_cache as _lru_cache
from pathlib import Path

from .config import get_settings
from .ffmpeg import ffmpeg_path

SEG_SECONDS = 4
# Within this many segments of the active frontier -> sequential, just wait.
# Beyond it (or before the start) -> a seek, so restart the transcode there.
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


def _seg(out_dir: Path, n: int) -> Path:
    return out_dir / f"seg_{n:05d}.ts"


def _exists(p: Path) -> bool:
    try:
        return p.exists() and p.stat().st_size > 0
    except OSError:
        return False


def _first_gap(out_dir: Path, start: int) -> int:
    """Smallest n >= start whose segment isn't on disk — i.e. the first segment
    that still needs producing, and the end of the contiguous run from start."""
    n = start
    while _exists(_seg(out_dir, n)):
        n += 1
    return n


# --- orphan reaping -------------------------------------------------------

def _pid_file() -> Path:
    return _cache_root() / "active.pids"


def _record_pid(pid: int) -> None:
    try:
        with open(_pid_file(), "a", encoding="utf-8") as f:
            f.write(f"{pid}\n")
    except OSError:
        pass


def reap_orphans() -> None:
    """Kill ffmpeg this app spawned in a previous run (recorded PIDs) so a
    restart doesn't leave a 4K transcode pinning a core. Segments are kept."""
    pf = _pid_file()
    if not pf.exists():
        return
    try:
        pids = [int(x) for x in pf.read_text().split() if x.strip().isdigit()]
    except OSError:
        pids = []
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass  # already gone (or reused — best-effort only)
    try:
        pf.unlink()
    except OSError:
        pass


# --- cache eviction -------------------------------------------------------

def _dir_size(p: Path) -> int:
    try:
        return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
    except OSError:
        return 0


def evict_if_needed() -> None:
    """Keep the cache under the configured cap, dropping least-recently-used
    file dirs first. Active (alive) sessions are never evicted."""
    cap_gb = get_settings().transcode_cache_gb
    if cap_gb <= 0:
        return
    cap = int(cap_gb * 1024**3)
    root = _cache_root()
    dirs = [d for d in root.iterdir() if d.is_dir()]
    total = sum(_dir_size(d) for d in dirs)
    if total <= cap:
        return
    protected = {str(fid) for fid, s in _sessions.items() if s.alive}
    for d in sorted(dirs, key=lambda d: d.stat().st_mtime):  # oldest first
        if total <= cap:
            break
        if d.name in protected:
            continue
        total -= _dir_size(d)
        shutil.rmtree(d, ignore_errors=True)


def startup_cleanup() -> None:
    _sessions.clear()
    reap_orphans()
    evict_if_needed()


# --- playlist + ffmpeg ----------------------------------------------------

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


@_lru_cache(maxsize=1)
def _use_nvenc() -> bool:
    """Whether to transcode on the GPU. 'auto' actually test-runs a tiny NVENC
    encode so a box with the encoder compiled in but no usable GPU still falls
    back to x264."""
    mode = get_settings().transcode_hwaccel.strip().lower()
    if mode == "cpu":
        return False
    if mode in ("nvenc", "gpu", "cuda"):
        return True
    try:
        r = subprocess.run(
            [ffmpeg_path(), "-hide_banner", "-f", "lavfi",
             "-i", "color=c=black:s=256x256:d=0.1",
             "-c:v", "h264_nvenc", "-f", "null", "-"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25,
        )
        return r.returncode == 0
    except Exception:
        return False


# libplacebo HDR(PQ/BT.2020) -> SDR(BT.709) tone-map, scaled + 8-bit, all on GPU.
_TONEMAP = (
    "tonemapping=bt.2390:colorspace=bt709:color_primaries=bt709:"
    "color_trc=bt709:format=nv12"
)


def _build_cmd(sess: "Session", start_num: int) -> list[str]:
    ff = ffmpeg_path()
    d = sess.decision
    transcode_video = d["video"] == "transcode"
    gpu = transcode_video and _use_nvenc()
    hdr = bool(d.get("hdr"))
    kf = f"expr:gte(t,n_forced*{SEG_SECONDS})"

    args = [ff, "-hide_banner", "-loglevel", "error", "-y"]

    # --- input + hardware decode -----------------------------------------
    if gpu and hdr:
        args += ["-init_hw_device", "vulkan"]
    if start_num > 0:
        args += ["-ss", str(start_num * SEG_SECONDS)]  # fast input seek
    if gpu and hdr:
        args += ["-hwaccel", "vulkan", "-hwaccel_output_format", "vulkan"]
    elif gpu:
        args += ["-hwaccel", "cuda", "-hwaccel_output_format", "cuda"]
    args += ["-i", sess.src]

    # --- video -----------------------------------------------------------
    if not transcode_video:
        args += ["-c:v", "copy"]
    elif gpu and hdr:
        args += [
            "-vf", f"libplacebo=w=1920:h=-2:{_TONEMAP},hwdownload,format=nv12",
            "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23",
            "-forced-idr", "1", "-force_key_frames", kf,
        ]
    elif gpu:
        args += [
            "-vf", "scale_cuda=1920:-2:format=nv12",
            "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23",
            "-forced-idr", "1", "-force_key_frames", kf,
        ]
    else:
        args += [
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            "-vf", "scale='min(1920,iw)':-2:flags=bicubic", "-pix_fmt", "yuv420p",
            "-force_key_frames", kf,
        ]

    # --- audio -----------------------------------------------------------
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
    # Run below normal priority so a transcode can use spare cores but always
    # yields to the web server — one stream must never starve playback/requests.
    kwargs: dict = {}
    if sys.platform == "win32":
        kwargs["creationflags"] = subprocess.BELOW_NORMAL_PRIORITY_CLASS
    else:
        kwargs["preexec_fn"] = lambda: os.nice(10)  # noqa: PLW1509
    proc = subprocess.Popen(
        _build_cmd(sess, start_num),
        stdout=subprocess.DEVNULL,
        stderr=log,
        **kwargs,
    )
    sess.proc = proc
    sess.start_num = start_num
    _record_pid(proc.pid)


def get_or_start(file_id, src_path, decision, duration) -> "Session":
    with _lock:
        existing = _sessions.get(file_id)
        if existing and existing.alive:
            existing.last_access = time.time()
            return existing

        out_dir = _cache_root() / str(file_id)
        out_dir.mkdir(parents=True, exist_ok=True)
        sess = Session(file_id, out_dir, src_path, decision, duration)

        if sess.vod:
            _write_vod_playlist(out_dir, duration)
            # Resume at the first gap; if the whole film is cached, no ffmpeg.
            last_seg = int(duration // SEG_SECONDS)
            start = _first_gap(out_dir, 0)
            if start <= last_seg:
                _spawn(sess, start)
        else:
            # copy/remux: variable-length segments, ffmpeg owns the playlist —
            # can't resume partials, so start clean.
            shutil.rmtree(out_dir, ignore_errors=True)
            out_dir.mkdir(parents=True, exist_ok=True)
            _spawn(sess, 0)

        _sessions[file_id] = sess
        evict_if_needed()
        return sess


def ensure_segment(file_id: int, seg_index: int) -> Path | None:
    """Return a segment's path, restarting the transcode at the seek point when
    it's outside the active frontier. The caller waits for the file to appear."""
    sess = _sessions.get(file_id)
    if sess is None:
        return None
    sess.last_access = time.time()
    path = _seg(sess.dir, seg_index)
    if _exists(path):
        return path  # cached (or just produced) — instant
    if not sess.vod:
        return path  # copy/remux: sequential, the caller just waits

    frontier = _first_gap(sess.dir, sess.start_num)  # first not-yet-made segment
    reachable = sess.alive and sess.start_num <= seg_index <= frontier + WAIT_AHEAD
    if not reachable:
        with _lock:
            if not _exists(path):
                _spawn(sess, seg_index)
    return path
