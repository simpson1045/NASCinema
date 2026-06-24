"""ffprobe wrapper — extract the stream facts that drive playback decisions.

Runs ffprobe via a thread (subprocess), because on Windows we're on a
SelectorEventLoop which can't do asyncio subprocesses.
"""

from __future__ import annotations

import asyncio
import json
import subprocess

from .ffmpeg import ffprobe_path


def _bit_depth(video: dict) -> int | None:
    raw = video.get("bits_per_raw_sample")
    if raw and str(raw).isdigit():
        return int(raw)
    pix = video.get("pix_fmt", "")
    if "10" in pix:
        return 10
    if "12" in pix:
        return 12
    if pix:
        return 8
    return None


def _is_hdr(video: dict) -> bool:
    transfer = (video.get("color_transfer") or "").lower()
    # PQ (HDR10/Dolby Vision base) or HLG.
    return transfer in {"smpte2084", "arib-std-b67"}


async def probe_file(path: str) -> dict | None:
    """Return normalized media facts for a file, or None if ffprobe is missing
    or the file can't be read."""
    exe = ffprobe_path()
    if not exe:
        return None

    args = [
        exe,
        "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        path,
    ]

    def _run() -> subprocess.CompletedProcess:
        return subprocess.run(args, capture_output=True, text=True, timeout=90)

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

    streams = data.get("streams", [])
    fmt = data.get("format", {})
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)

    def _num(d: dict, key: str, cast):
        v = d.get(key)
        try:
            return cast(v) if v is not None else None
        except (ValueError, TypeError):
            return None

    return {
        "container": (fmt.get("format_name") or "").split(",")[0] or None,
        "duration": _num(fmt, "duration", float),
        "size_bytes": _num(fmt, "size", int),
        "video_codec": video.get("codec_name") if video else None,
        "audio_codec": audio.get("codec_name") if audio else None,
        "width": video.get("width") if video else None,
        "height": video.get("height") if video else None,
        "bit_depth": _bit_depth(video) if video else None,
        "hdr": _is_hdr(video) if video else False,
    }
