"""Track Manager rules — which audio/subtitle tracks a strip keeps.

Implements docs/SPEC-track-manager.md §3 exactly (hard-won rules; don't
"improve" them without Matt). Pure functions over plain dicts so they can be
tested without a database or files:

    stream = {"index", "kind", "codec", "language", "title",
              "is_default", "is_forced", "bit_rate", "channels"}

`plan_file()` returns what a strip would do to one file — nothing here touches
a file.
"""

from __future__ import annotations

import re

# Untagged tracks that are really dubs/voiceovers (Cyrillic, or the usual
# Russian voiceover markers). Sorcerer's Stone had an untagged 'DVO, LDV /
# "Легендарный"' track as audio #1 — it survived an "eng + und" rule and played
# by default.
DUB_RE = re.compile(
    r"[Ѐ-ӿ]|\b(dvo|mvo|avo|dub|dubbed|voice.?over|gavrilov|volodarsky|rus|ukr)\b",
    re.IGNORECASE,
)

# Fan preservations (Harmy Despecialized, 4K77/80/83, 35mm scans, open matte
# reels…) carry irreplaceable alternate English mixes, often with odd language
# tags — language-based stripping would destroy them. Never touched.
PROTECTED_RE = re.compile(
    r"harmy|4k77|4k80|4k83|35mm|despecial|open.?matte|reel|print|scan|fan.?edit|preserv",
    re.IGNORECASE,
)

_ENGLISH = {"eng", "en"}
_UNTAGGED = {"", "und"}


def _lang(s: dict) -> str:
    return (s.get("language") or "").strip().lower()


def is_english(s: dict) -> bool:
    return _lang(s) in _ENGLISH


def is_commentary(s: dict) -> bool:
    return "comment" in (s.get("title") or "").lower()


def keep_track(s: dict) -> tuple[bool, str]:
    """(keep?, why) for one audio or subtitle track."""
    lang = _lang(s)
    if lang in _ENGLISH:
        return True, "English"
    if lang in _UNTAGGED:
        if DUB_RE.search(s.get("title") or ""):
            return False, "Untagged dub/voiceover"
        return True, "Untagged (no dub markers)"
    return False, f"Foreign ({lang})"


def protected_reason(path: str, manual: bool = False) -> str | None:
    if manual:
        return "Protected by you"
    m = PROTECTED_RE.search(path or "")
    if m:
        return f"Fan preservation ('{m.group(0)}' in the name)"
    return None


def _size(s: dict, duration: float | None) -> int | None:
    br = s.get("bit_rate")
    if not br or not duration:
        return None
    return int(br * duration / 8)


def plan_file(path: str, duration: float | None, streams: list[dict],
              manual_protect: bool = False) -> dict:
    """What a strip would do to one file.

    status: "strip" (something to drop), "clean" (nothing to drop — never
    rewritten), "protected", or "no_english" (no audio would survive — skipped
    and logged).
    """
    rows = []
    for s in sorted(streams, key=lambda s: s["index"]):
        kind = s.get("kind")
        if kind in ("audio", "subtitle"):
            keep, why = keep_track(s)
        else:
            keep, why = True, "Video"
        rows.append({**s, "keep": keep, "why": why,
                     "est_bytes": _size(s, duration),
                     "commentary": kind == "audio" and is_commentary(s)})

    audio = [r for r in rows if r["kind"] == "audio"]
    kept_audio = [r for r in audio if r["keep"]]
    dropped = [r for r in rows if not r["keep"]]
    first_audio = audio[0] if audio else None
    default_audio = next((r for r in audio if r.get("is_default")), first_audio)

    # Kept audio: English-tagged first, commentary last (stable otherwise).
    order = sorted(kept_audio, key=lambda r: (r["commentary"], not is_english(r)))
    new_default = order[0]["index"] if order else None

    savings = sum(r["est_bytes"] or 0 for r in dropped)
    plan = {
        "path": path,
        "duration": duration,
        "streams": rows,
        "audio_order": [r["index"] for r in order],
        "new_default_audio": new_default,
        "drop_count": len(dropped),
        "savings_bytes": savings,
        # A dropped track with no bitrate (no BPS tag) isn't in the estimate.
        "savings_partial": any(r["est_bytes"] is None and r["kind"] == "audio"
                               for r in dropped),
        # The ⚠ badge: players start on a track the rules call foreign.
        "foreign_default": bool(default_audio and not default_audio["keep"]),
        "protected": None,
    }

    reason = protected_reason(path, manual_protect)
    if reason:
        plan.update(status="protected", protected=reason)
    elif audio and not kept_audio:
        plan["status"] = "no_english"
    elif not dropped:
        plan["status"] = "clean"
    else:
        plan["status"] = "strip"
    return plan
