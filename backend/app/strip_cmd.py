"""The pure parts of a strip (app/strip.py): the ffmpeg command for a plan
and the check of the staged copy. No I/O — unit-tested in
backend/tests/test_strip_cmd.py.
"""

from __future__ import annotations

DURATION_SLACK = 15.0  # seconds (a long dropped dub can shorten the file)


def ffmpeg_args(exe: str, src: str, dst: str, plan: dict, fmt: str) -> list[str]:
    """The stream-copy command for a plan from track_rules.plan_file()."""
    kept = [r for r in plan["streams"] if r["keep"]]
    video = [r["index"] for r in kept if r["kind"] == "video"]
    audio = plan["audio_order"]
    subs = [r for r in kept if r["kind"] == "subtitle"]
    args = [exe, "-hide_banner", "-nostdin", "-y", "-i", src]
    for i in video:
        args += ["-map", f"0:{i}"]
    for i in audio:
        args += ["-map", f"0:{i}"]
    for r in subs:
        args += ["-map", f"0:{r['index']}"]
    if fmt == "matroska":
        args += ["-map", "0:t?"]        # attachments: fonts for styled subtitles
    args += ["-map_chapters", "0", "-map_metadata", "0", "-c", "copy",
             "-max_muxing_queue_size", "9999"]
    for j in range(len(audio)):
        args += [f"-disposition:a:{j}", "default" if j == 0 else "0"]
    for j, r in enumerate(subs):
        args += [f"-disposition:s:{j}", "forced" if r.get("is_forced") else "0"]
    args += ["-progress", "pipe:1", "-nostats", "-f", fmt, dst]
    return args


def verify(plan: dict, out: dict | None, src_duration: float | None) -> str | None:
    """None if the staged copy is what the plan asked for, else why not."""
    if not out:
        return "the new file can't be read"
    rows = plan["streams"]
    want = {
        "video": sum(1 for r in rows if r["keep"] and r["kind"] == "video"),
        "audio": len(plan["audio_order"]),
        "subtitle": sum(1 for r in rows if r["keep"] and r["kind"] == "subtitle"),
    }
    st = out.get("streams") or []
    got = {k: sum(1 for s in st if s["kind"] == k) for k in want}
    if got != want:
        return f"track counts {got} — expected {want}"
    d = out.get("duration")
    if src_duration and (d is None or abs(d - src_duration) > DURATION_SLACK):
        return f"duration {d} s vs {src_duration} s"
    audio = [s for s in st if s["kind"] == "audio"]
    if audio:
        planned = next(r for r in rows if r["index"] == plan["audio_order"][0])
        first = audio[0]
        if (first.get("codec"), first.get("language"), first.get("title")) != (
                planned.get("codec"), planned.get("language"), planned.get("title")):
            return "the first audio track isn't the planned default"
        if not first.get("is_default") or any(s.get("is_default") for s in audio[1:]):
            return "default audio flag isn't only on the first track"
    return None
