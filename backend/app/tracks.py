"""Versions + tracks for the pickers: turn probe data into what a person reads.

A movie can have several feature files (ANH: 4K UHD remux, 4K77, Harmy,
Respecialized), each with many audio/subtitle tracks whose embedded titles are
the real information ("1.0 DTS-HD-MA (1977 35mm mono mix)"). Here each file gets
a version label and each track a title + a tidy description, plus mpv's
per-type track number (`--aid` / `--sid` are 1-based within audio/subtitles).
"""

from __future__ import annotations

import os
import re

from .models import MediaFile, MediaStream

_LANGS = {
    "eng": "English", "en": "English", "fra": "French", "fre": "French",
    "fr": "French", "spa": "Spanish", "es": "Spanish", "ger": "German",
    "deu": "German", "de": "German", "ita": "Italian", "it": "Italian",
    "jpn": "Japanese", "ja": "Japanese", "por": "Portuguese", "pt": "Portuguese",
    "rus": "Russian", "ru": "Russian", "ukr": "Ukrainian", "pol": "Polish",
    "cze": "Czech", "ces": "Czech", "hun": "Hungarian", "chi": "Chinese",
    "zho": "Chinese", "kor": "Korean", "dut": "Dutch", "nld": "Dutch",
    "swe": "Swedish", "nor": "Norwegian", "dan": "Danish", "fin": "Finnish",
    "tha": "Thai", "hin": "Hindi", "ara": "Arabic", "heb": "Hebrew",
    "tur": "Turkish", "gre": "Greek", "ell": "Greek", "nav": "Navajo",
}

_AUDIO_CODECS = {
    "truehd": "TrueHD", "eac3": "Dolby Digital Plus", "ac3": "Dolby Digital",
    "dts": "DTS", "flac": "FLAC", "aac": "AAC", "opus": "Opus", "mp3": "MP3",
}
_SUB_CODECS = {
    "hdmi_pgs_subtitle": "PGS", "hdmv_pgs_subtitle": "PGS", "subrip": "SRT",
    "ass": "ASS", "ssa": "SSA", "dvd_subtitle": "VobSub", "mov_text": "Text",
    "webvtt": "WebVTT",
}
_LOSSLESS = {"truehd", "flac", "alac"}

# Bracket tags that describe the encode, not the version.
_NOT_A_VERSION = re.compile(
    r"^(\d{3,4}p|4k|uhd|hdr\d*|dv|sdr|bluray|blu-ray|bdrip|brrip|web(-?dl|rip)?|"
    r"remux|x26[45]|h\.?26[45]|hevc|avc|10bit|[57]\.1|2\.0|atmos|truehd|dts.*|"
    r"yts(\.\w+)?|rarbg|proper|repack|\d{4})$",
    re.IGNORECASE,
)


def lang_name(code: str | None) -> str:
    if not code or code.lower() in ("und", "zxx", "mis"):
        return "Unknown language"
    return _LANGS.get(code.lower(), code.upper())


def _channels(st: MediaStream) -> str:
    n = st.channels or 0
    return {1: "Mono", 2: "Stereo", 3: "3.0", 6: "5.1", 7: "6.1", 8: "7.1"}.get(
        n, f"{n} ch" if n else "")


def _audio_codec(st: MediaStream) -> str:
    c = (st.codec or "").lower()
    prof = (st.profile or "").upper()
    if c == "dts":
        if "MA" in prof:
            return "DTS-HD MA"
        if "HRA" in prof or "HI RES" in prof:
            return "DTS-HD HRA"
        if "X" in prof:
            return "DTS:X"
    if c == "eac3" and "ATMOS" in prof:
        return "Dolby Digital Plus Atmos"
    if c == "truehd" and "ATMOS" in prof:
        return "TrueHD Atmos"
    if c.startswith("pcm"):
        return "PCM"
    return _AUDIO_CODECS.get(c, c.upper() or "Audio")


def version_label(mf: MediaFile) -> str:
    """"4K77", "Harmy Despecialized", "Respecialized 1997 SE", else a quality
    summary like "4K · HDR · TrueHD 7.1"."""
    if mf.edition:
        return mf.edition
    name = os.path.splitext(os.path.basename(mf.path or ""))[0]
    for tag in re.findall(r"\[([^\]]+)\]", name):
        if not _NOT_A_VERSION.match(tag.strip()):
            return tag.strip()
    return quality_label(mf)


def quality_label(mf: MediaFile) -> str:
    w, h = mf.width or 0, mf.height or 0
    lines = max(h, round(w * 9 / 16))
    res = "4K" if lines >= 2000 else "1080p" if lines >= 1000 else \
        "720p" if lines >= 700 else "SD" if lines else ""
    parts = [p for p in (res, "HDR" if mf.hdr else "") if p]
    main = next((s for s in sorted(mf.streams, key=lambda s: s.index)
                 if s.kind == "audio" and s.is_default), None) or next(
        (s for s in sorted(mf.streams, key=lambda s: s.index) if s.kind == "audio"),
        None)
    if main:
        parts.append(f"{_audio_codec(main)} {_channels(main)}".strip())
    return " · ".join(parts) or "Version"


# Names that say nothing on their own ("|ORIGINAL|", "Surround 7.1") — shown
# with the language/codec after them instead of alone.
_GENERIC = re.compile(
    r"^(original|main|default|english|eng|audio|track\s*\d*|full|"
    r"(surround|stereo|mono|dolby|dts)(\s*[\d.]+)?)$",
    re.IGNORECASE,
)


def clean_title(raw: str | None) -> str:
    """Tidy a track name from the file: strip stray |, [], quotes and
    underscores ("|ORIGINAL|" -> "Original", "SDH_full" -> "SDH (full)").
    Real names pass through ("1.0 DTS-HD-MA (1977 35mm mono mix)")."""
    t = (raw or "").strip().strip("|[]{}\"' ").replace("_", " ")
    t = re.sub(r"\s+", " ", t).strip()
    m = re.match(r"^(SDH|CC|HI)\s+(.+)$", t, flags=re.IGNORECASE)
    if m:
        t = f"{m.group(1).upper()} ({m.group(2)})"
    if t and (t.isupper() or t.islower()) and len(t) <= 16 and " " not in t:
        t = t.capitalize()  # "ORIGINAL"/"full" -> "Original"/"Full"
    return t


def track_rows(mf: MediaFile) -> dict:
    """{"audio": [...], "subtitles": [...]} in file order, each with mpv's
    1-based per-type id, a display title, a description and flags."""
    audio, subs = [], []
    for st in sorted(mf.streams, key=lambda s: s.index):
        title = clean_title(st.title)
        if st.kind == "audio":
            codec = _audio_codec(st)
            desc = " · ".join(p for p in (lang_name(st.language), codec,
                                          _channels(st)) if p)
            if title and _GENERIC.match(title):
                # "Original · English DTS-HD MA 5.1" — the name alone says nothing.
                title, desc = f"{title} · {desc.replace(' · ', ' ')}", ""
            audio.append({
                "id": len(audio) + 1,
                "title": title or desc,
                "desc": desc,
                "language": st.language,
                "lossless": (st.codec or "").lower() in _LOSSLESS
                or codec in ("DTS-HD MA", "PCM") or (st.codec or "").startswith("pcm"),
                "commentary": "comment" in title.lower(),
                "default": bool(st.is_default),
                "channels": st.channels,
            })
        elif st.kind == "subtitle":
            codec = _SUB_CODECS.get((st.codec or "").lower(), (st.codec or "").upper())
            desc = " · ".join(p for p in (lang_name(st.language), codec,
                                          "Forced" if st.is_forced else "") if p)
            subs.append({
                "id": len(subs) + 1,
                "title": title or lang_name(st.language),
                "desc": desc,
                "language": st.language,
                "forced": bool(st.is_forced),
                "default": bool(st.is_default),
            })
    return {"audio": audio, "subtitles": subs}
