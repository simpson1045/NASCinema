# NASCinema — Changelog

The in-app updater shows the newest `## ` section below. Newest on top.

## 0.6.3 - 2026-09-25
- **Fullscreen logos line up:** the movie logo now sits centered over the year · IMDb · Rotten Tomatoes · quality row, whatever their widths.

## 0.6.2 - 2026-09-25
- **Trailer button fixed:** only true HDR trailers switch to the HDR player now — no more screen glitch on regular trailers. In HDR trailers the controller works (A pause, ←/→ skip, B back) and the controls show up.
- **Sequel logos:** movies whose only logo is the series logo (like *The Land Before Time VIII*) now show their subtitle in gold underneath — and most sequels get their own proper logo instead of the series one.
- **Better trailer picks:** when Apple only has a low-res trailer, the studio's HD YouTube trailer is used instead.
- The HDR trailers setting is gold like the other settings.

## 0.6.1 - 2026-09-25
- **The movie player got a glow-up.** New on-screen controls in NASCinema's navy and gold: a title bar, a slim gold timeline with preview thumbnails when you scrub, chapter marks, and time remaining — all fading away while you watch.
- **Full controller control while watching:** **A** play/pause · **←/→** skip 10 seconds · **LB/RB** previous/next chapter · **X** audio track · **Y** subtitles · **Start** menu · **↑/↓** show the controls · **B** back out (or close a menu) · **View** flag a problem.

## 0.6.0 - 2026-09-25
- **Trailers now come from Apple TV** — the studio's own trailers instead of YouTube uploads: the real theatrical trailer (no "now in 4K" re-release promos), 2–3× the picture quality, 5.1 surround, and 4K HDR when Apple has it. The whole library is being switched over in the background; movies Apple doesn't cover keep their YouTube trailer.
- **HDR trailers** — Settings → Display → *HDR trailers*: **Auto** (default — uses HDR when it's switched on for your display), Always, or Never. In Big Picture, HDR trailers play full screen through the same player as your 4K HDR movies.

## 0.5.9 - 2026-09-25
- **New: the flag button.** Something look or sound wrong? Press **View** (the two-squares button) on the controller — or **F8** on the keyboard — right when it happens. NASCinema saves a screenshot plus which movie or trailer was playing and exactly where, shows "Flagged ✓", and gets out of your way. No need to stop and describe it; Claude reads the flags and fixes them.
- View no longer works as Back — use **B** (it always did the same thing).

## 0.5.8 - 2026-09-25
- **The mouse cursor hides while you use the controller or keyboard** — it disappears the moment you press a button and comes back as soon as you move the mouse.
- **Trailers play in English.** YouTube now auto-dubs many trailers into other languages, and the downloader sometimes grabbed a dub (German, Portuguese…). It now always takes the original audio, and the affected trailers were re-downloaded — keeping their 4K picture.

## 0.5.7 - 2026-09-25
- **Correct quality labels.** Widescreen movies stored without their black bars (1920x800) showed "720p" and 4K ones (3840x1600) showed "1080p" — about half the library. Labels now go by the real picture size.

## 0.5.6 - 2026-09-25
- **Trailers decode in software** to get rid of the dotted patch that flickered in the middle of every trailer (the graphics card's video decoder is the suspect). Movies are unaffected.
- Trailers across the library were checked: wrong ones (other movies, TV teasers, fan edits, foreign dubs) were replaced with official English trailers. Terminator 2 now has its original 1991 trailer.

## 0.5.5 - 2026-09-25
- **Fixed the crash when flipping through trailers** — the featured area now keeps one video player instead of creating and destroying one per trailer.
- **The top of the screen follows what you highlight** — as you move through the rows, the backdrop, title and (after a moment) the trailer switch to the highlighted movie. Press Up to get back to the featured rotation.
- Trailers now come only from each movie's official trailer list; Sorcerer's Stone has its real trailer and the US poster.

## 0.5.4 - 2026-09-25
- **Updates install for real now** — NASCinema uses NASRadio's proven updater. When you update, a small "NASCinema Update" window shows progress, closes itself, and the new version opens.
- Includes 0.5.3: the new Big Picture movie page with in-app trailers and playable extras, and right-stick scrolling.

## 0.5.3 - 2026-09-25
- **New Big Picture movie page** — full backdrop, logo, ratings and description, big **Play / Resume** and **Trailer** buttons (the trailer plays right here, fullscreen), and the movie's **extras** as a row you can play. Left/Right move, Up/Down switch between the buttons and the extras, A plays, B goes back.
- **Extras play** — they used to say "coming soon".
- **Right stick scrolls** any page.

## 0.5.2 - 2026-09-25
- **Updates actually install now.** Since 0.4.2 the app closed to update and then nothing happened — the background installer never started (Windows gave it no console, so it quit instantly). It now runs hidden and reliably: the app closes, updates, and reopens by itself.
- Includes everything from 0.5.0 and 0.5.1: Big Picture mode, Xbox controller support, the fixed library, and sharper trailers.

## 0.5.1 - 2026-09-25
- **Xbox controller support** in Big Picture: D-pad or left stick to move (hold to keep moving), **A** to open, **B** to go back, **Start** for the menu. Up from the first row makes the featured trailer fullscreen with sound; Left/Right there changes the movie.
- The controller also works in menus, the update prompt and the movie page: D-pad moves between buttons, A presses, B goes back.
- **Your library is fixed:** Jurassic World, Fallen Kingdom and Dominion are back as their own movies (they were filed under Rebirth), Deathly Hallows Part 2 is no longer filed under Part 1, and ~118 blank "Bonus Features" tiles are gone — those files are now extras on their real movies.
- **Sharper trailers** across the library, and trailers are being fetched for every movie.

## 0.5.0 - 2026-09-24
- **Big Picture mode** — a fullscreen TV layout built to match the Roku channel. NASCinema now opens straight into it on this PC (turn that off in Settings → Display → "Start in Big Picture").
  - The featured movie fills the whole screen with its trailer; logo, ratings and description sit on the left. Letterboxed trailers are never zoomed or cropped.
  - Two rails visible at once; the rail you're on stays in place and the rest scroll under it. Continue Watching shows wide cards with a progress bar.
  - **Keyboard:** arrows move, Enter opens, Esc goes back. Up from the first rail makes the featured trailer fullscreen with sound; Left/Right changes the featured movie. Esc on the home screen opens a menu: Exit Big Picture / Settings / Quit.
  - Xbox controller support is next.
- **Big Picture button** (TV icon) in the regular app bar to switch back in.
- **Featured info no longer floats mid-screen** in the regular layout — it's on the left, like the Roku.

## 0.4.2 - 2026-09-24
- **Updates install silently on Windows** — no more black command window that hangs until you press Ctrl+C. The app closes, updates in the background, reopens itself, and cleans up the downloaded files.
- **Heads-up for THIS update only:** it's still installed by the old updater, so the black window may appear one last time — press Ctrl+C in it and the update finishes. Every update after this one is silent.

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
