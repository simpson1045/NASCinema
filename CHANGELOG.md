# NASCinema — Changelog

The in-app updater shows the newest `## ` section below. Newest on top.

## 0.3.8 - 2026-06-25
- **Native ELKO renderer** (media_kit/libmpv): direct-plays HEVC/HDR/TrueHD off disk — no server transcode.
- **Capability-aware playback**: the native client direct-plays; the browser still gets the honest transcode + "why" badge.
- **Chromecast from the phone**: pure-Dart CASTV2 sender (works over plain HTTP, no HTTPS), with a device picker.
- **Phone-as-remote**: casting hands off to a remote screen; the session survives navigation so you can browse and cast another movie.
- **Stats for nerds**: an in-player overlay of the probed source + live playback facts.
- **In-app updates**: check / download / install from the server, built by `backend/release.bat`.
