"""Playback decision engine: Direct Play -> Remux -> Transcode.

Given a file's probed streams and a client profile, decide the cheapest path
that will actually play — and produce a plain-English reason. The reason is the
thing Plex/JF hide; we surface it ("why am I transcoding?").
"""

from __future__ import annotations

# What a browser (our web client) can play natively.
BROWSER_VIDEO = {"h264"}
BROWSER_AUDIO = {"aac", "mp3"}
BROWSER_CONTAINERS = {"mov", "mp4", "m4v"}


def decide(
    *,
    video_codec: str | None,
    audio_codec: str | None,
    container: str | None,
    hdr: bool,
    client: str = "web",
) -> dict:
    v = (video_codec or "").lower()
    a = (audio_codec or "").lower()
    c = (container or "").lower()

    video_ok = v in BROWSER_VIDEO
    audio_ok = a in BROWSER_AUDIO
    container_ok = c in BROWSER_CONTAINERS

    if video_ok and audio_ok and container_ok and not hdr:
        return {
            "mode": "direct",
            "reason": f"Direct play — {v.upper()}/{a.upper()} in a browser-native "
            "container. No re-encoding, no CPU.",
            "video": "copy",
            "audio": "copy",
            "hdr": hdr,
        }

    if video_ok and audio_ok and not hdr:
        return {
            "mode": "remux",
            "reason": f"Remuxing — the streams are already browser-compatible "
            f"({v.upper()}/{a.upper()}); just repackaging the container. Near-zero CPU.",
            "video": "copy",
            "audio": "copy",
            "hdr": hdr,
        }

    reasons: list[str] = []
    video_action = "copy"
    audio_action = "copy"
    if not video_ok:
        reasons.append(f"video is {v.upper() or 'unknown'} (browser needs H.264)")
        video_action = "transcode"
    if hdr:
        reasons.append("HDR video isn't browser-displayable")
        video_action = "transcode"
    if not audio_ok:
        reasons.append(f"audio is {a.upper() or 'unknown'} (browser needs AAC)")
        audio_action = "transcode"

    return {
        "mode": "transcode",
        "reason": "Transcoding — " + "; ".join(reasons) + ".",
        "video": video_action,
        "audio": audio_action,
        "hdr": hdr,
    }
