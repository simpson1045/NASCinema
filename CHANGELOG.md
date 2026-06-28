# NASCinema — Changelog

The in-app updater shows the newest `## ` section below. Newest on top.

## 0.3.12 - 2026-06-28
- **Casting to the TV now actually plays.** The branded NASCinema now-playing screen was coming up but the movie never started — the receiver was crashing on startup (it referenced a Cast SDK event that no longer exists). Fixed: video **and** audio now play on the branded screen.
- **Phone playback shows the honest badge** — no more false "DIRECT" on the phone; it correctly transcodes.
- **Cast button on the home screen** — connect to the TV first, then pick a movie.
- **Play sends it to the TV when connected** — once you're connected to a TV, a movie's amber Play button casts straight to the TV and turns your phone into the remote (no need to open the local player and tap cast).
- **Remote reconnects when you come back** — locking the phone or switching apps no longer leaves the remote dead. The movie keeps playing on the TV, and when you return to NASCinema it silently rejoins the TV so the remote works again.
- **Branded TV screen is fully custom** — the default Chromecast overlay (title/scrubber/seek/CC) no longer covers our now-playing screen on pause; on pause you see the actual movie frame with a clean bottom gradient. (Receiver-side; applies to any app version.)
- **Reliable cast connect** — if the branded receiver ever can't launch, casting automatically falls back to the default Chromecast receiver, so it always connects.

## 0.3.11 - 2026-06-27
- **Custom NASCinema TV receiver is live** — casting now shows the branded now-playing screen on the TV (blurred backdrop, title, progress + "ends at" ETA, stats overlay, Art-Mode idle) instead of the generic Chromecast screen. Media is routed over HTTPS so it loads cleanly.
- Update notice is now a banner on the library, not a SnackBar that could appear under the player.

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
