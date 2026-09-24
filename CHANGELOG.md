# NASCinema — Changelog

The in-app updater shows the newest `## ` section below. Newest on top.

## 0.4.1 - 2026-09-24
- **Netflix-style home hero** — the featured movie at the top now works like the Roku: shuffled picks, the backdrop first, then the movie's trailer fades in over it (only once it's actually playing, so a missing trailer just leaves the backdrop). Hover the hero for a moment and it expands to fill the screen with sound on. Every change fades through black instead of snapping.
- **TrueHD plays reliably** — TrueHD tracks now decode to lossless multichannel PCM by default instead of bitstreaming, which dropped out at seamless-branch splices (e.g. ROTS at 2:20). Same lossless audio, the Denon shows "Multi Ch In". DTS-HD, Dolby Digital Plus and Dolby Digital still bitstream. Toggle in Settings → Renderer once the upstream mpv fix lands.
- **New Settings screen** (gear icon on the library bar) with optional theater hooks, all OFF until you turn them on:
  - **Denon** — power on the AVR and switch to the ELKO input when you press Play.
  - **LG TV** — pair once (accept the prompt on the TV), then optionally switch the TV input on Play. The "keep the input from being relabeled PC" option is experimental — the TV may refuse it; a fix is coming.
  - **Refresh-rate match** — switch the display to the movie's frame rate (23.976 etc.) on Play and back on stop.
- **Server moved to the NAS** — the backend now runs on NorthsideNAS; the app's server address is unchanged.

## 0.4.0 - 2026-07-01
- **The player is now built into the app.** On Windows, Play launches a native mpv renderer embedded in the app window — full-quality 4K HDR / Dolby Vision picture and lossless TrueHD/Atmos/DTS-HD bitstream to the AVR, reading straight off the NAS. No separate player window, no transcode.
- **On-video controls, NASCinema-styled** — amber-themed controls appear on mouse move and hide when idle; back and fullscreen buttons, subtitle/audio pickers, and a stats page are all wired in. Hotkeys: Esc/Backspace exit, C subtitles, P audio, I stats, F fullscreen.
- **True HDR output** — the app passes HDR through to the display instead of tone-mapping it down to SDR ("vibrant now").
- **Crisp on 4K displays** — fixed a DPI bug that rendered the app at 2560-wide on a 4K screen.
- **No orphaned players** — mpv is chained to the app's lifetime at the kernel level, so closing (or crashing) the app can never leave audio playing in the background.
- **Search** — a search icon in the library bar with type-ahead results.
- **Auto-connect** — a saved server goes straight to the library; the connect form only appears on first run or failure.
- **The window remembers itself** — size, position, maximized, and fullscreen state persist across launches.

## 0.3.12 - 2026-06-28
- **Casting to the TV now actually plays.** The branded NASCinema now-playing screen was coming up but the movie never started — the receiver was crashing on startup (it referenced a Cast SDK event that no longer exists). Fixed: video **and** audio now play on the branded screen.
- **Phone playback shows the honest badge** — no more false "DIRECT" on the phone; it correctly transcodes.
- **Cast button on the home screen** — connect to the TV first, then pick a movie.
- **Play sends it to the TV when connected** — once you're connected to a TV, a movie's amber Play button casts straight to the TV and turns your phone into the remote (no need to open the local player and tap cast).
- **Remote reconnects when you come back** — locking the phone or switching apps no longer leaves the remote dead. The movie keeps playing on the TV, and when you return to NASCinema it silently rejoins the TV so the remote works again.
- **The remote isn't blank after reconnecting** — when it rejoins the TV it now re-reads what's playing (title, progress, subtitle list), instead of showing an empty remote.
- **Resume where you left off** — movies remember your position and which subtitle was on, locally and when casting. Re-open or re-cast a movie and it picks up where you stopped with your subtitle re-enabled — no more seeking from the start.
- **Accurate resume point when casting** — pressing Stop now pulls the live position from the TV before saving (and the position is saved when you background the app), so it no longer resumes a few minutes behind where you actually were.
- **Branded TV screen is fully custom** — the default Chromecast overlay (title/scrubber/seek/CC) no longer covers our now-playing screen on pause; on pause you see the actual movie frame with a clean bottom gradient. (Receiver-side; applies to any app version.)
- **Reliable cast connect** — if the branded receiver ever can't launch, casting automatically falls back to the default Chromecast receiver, so it always connects.
- **Refresh actually re-scans the library** — the Refresh button now re-scans the disk: it adds new files **and removes ones you deleted** (clearing their cached transcode), instead of only re-reading the database. No more playing a copy you already deleted.

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
