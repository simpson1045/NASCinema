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


def _dv_profile(video: dict) -> int | None:
    """Dolby Vision profile from the DOVI configuration side data, if any."""
    for sd in video.get("side_data_list") or []:
        if "dovi" in (sd.get("side_data_type") or "").lower():
            try:
                return int(sd.get("dv_profile"))
            except (TypeError, ValueError):
                return None
    return None


def _hdr_format(video: dict) -> str:
    if _dv_profile(video) is not None:
        return "dolby_vision"
    transfer = (video.get("color_transfer") or "").lower()
    if transfer == "smpte2084":
        return "hdr10"
    if transfer == "arib-std-b67":
        return "hlg"
    return "sdr"


def _frame_rate(video: dict) -> float | None:
    raw = video.get("avg_frame_rate") or video.get("r_frame_rate") or ""
    num, _, den = raw.partition("/")
    try:
        n, d = float(num), float(den or 1)
        return round(n / d, 3) if d else None
    except ValueError:
        return None


def _flag(disp: dict, key: str) -> bool:
    try:
        return bool(int(disp.get(key, 0)))
    except (TypeError, ValueError):
        return False


def _stream_row(s: dict) -> dict | None:
    """Normalize one ffprobe stream into a media_streams row, or None for
    stream types we don't keep (attachments, data)."""
    kind = s.get("codec_type")
    if kind not in {"video", "audio", "subtitle"}:
        return None
    tags = s.get("tags") or {}
    disp = s.get("disposition") or {}

    def _int(v):
        try:
            return int(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    row = {
        "index": s.get("index"),
        "kind": kind,
        "codec": s.get("codec_name"),
        "profile": s.get("profile"),
        "language": tags.get("language") or tags.get("LANGUAGE"),
        "title": tags.get("title") or tags.get("TITLE"),
        "is_default": _flag(disp, "default"),
        "is_forced": _flag(disp, "forced"),
        "bit_rate": _int(s.get("bit_rate") or tags.get("BPS")),
    }
    if kind == "audio":
        row.update(
            channels=_int(s.get("channels")),
            channel_layout=s.get("channel_layout"),
            sample_rate=_int(s.get("sample_rate")),
        )
    elif kind == "video":
        row.update(
            width=s.get("width"),
            height=s.get("height"),
            bit_depth=_bit_depth(s),
            frame_rate=_frame_rate(s),
            hdr_format=_hdr_format(s),
            dv_profile=_dv_profile(s),
        )
    return row


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
        # ffprobe emits UTF-8; bare text=True decodes with the locale codepage
        # (cp1252 on Windows) and DIES on files whose stream tags contain
        # multi-byte UTF-8 — the probe then silently fails on healthy files.
        return subprocess.run(
            args,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=90,
        )

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
        # Every video/audio/subtitle track — feeds media_streams.
        "streams": [r for r in (_stream_row(s) for s in streams) if r],
    }
