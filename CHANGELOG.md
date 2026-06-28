# NASCinema — Changelog

The in-app updater shows the newest `## ` section below. Newest on top.

## 0.3.10 - 2026-06-27
- **Subtitle track picker** on the cast remote — pick any track, not just on/off.
- **Stats for nerds on the remote** — an info button shows what's casting (stream, source codec/res/HDR, container); mirrors onto the TV with the custom receiver.
- **Custom NASCinema TV receiver** (groundwork) — a branded now-playing screen: blurred backdrop, title/clearlogo, progress with an "ends at" ETA, paused-logo in the corner, stats overlay, Art-Mode idle. Activates once it's HTTPS-hosted + registered.

## 0.3.9 - 2026-06-25
- **Roku-style cast remote**: a D-pad ring (play/pause, seek ±10, volume) over buttons for subtitles, library, and stop. Subtitles and volume are now controllable from the phone (volume hides when the AV chain owns it).
- **Force audio passthrough** (native renderer): an opt-in toggle to bitstream TrueHD/Atmos/DTS-HD straight to your AVR — no PC decode.

## 0.3.8 - 2026-06-25
- **Native ELKO renderer** (media_kit/libmpv): direct-plays HEVC/HDR/TrueHD off disk — no server transcode.
- **Capability-aware playback**: the native client direct-plays; the browser still gets the honest transcode + "why" badge.
- **Chromecast from the phone**: pure-Dart CASTV2 sender (works over plain HTTP, no HTTPS), with a device picker.
- **Phone-as-remote**: casting hands off to a remote screen; the session survives navigation so you can browse and cast another movie.
- **Stats for nerds**: an in-player overlay of the probed source + live playback facts.
- **In-app updates**: check / download / install from the server, built by `backend/release.bat`.
