# NASCinema — Handoff (honest current state)

*Last updated: 2026-06-30. This is the truthful state of the project for the next
session. The vision and full plan live in [README.md](README.md) and
[ROADMAP.md](ROADMAP.md) — **read those first**; this file is just "where we
actually are and what's next." Current version: **v0.3.13+12**.*

---

## Latest session (2026-06-30)

- **Roku playback "never worked" — root-caused & fixed.** The library was never
  rescanned after the NAS consolidation, so every `media_files.path` was stale
  (`\\NorthsideNAS\...\Totally Legal Movies\Totally Legal Movies\...` doubled
  hostname path) → `/api/stream/{id}/direct` 404'd → Roku bailed at pos=0s.
  Reran the scan (287 files re-added at `\\192.168.0.248\...`), then deleted 439
  stale `NorthsideNAS` media_files the prune guard skipped. Stream now serves
  HTTP 206 w/ range, direct + via NPM.
- **Side effect:** Continue Watching emptied (its progress was pinned to the
  deleted dead files). Will refill as movies are watched.
- **Roku audio:** ROTS direct-play then surfaced `audio=mat` (TrueHD) → silence +
  freeze ~6s. Roku can't bitstream TrueHD/DTS-HD. Shipped on-device audio-track
  selection (`scoreAudio`/`onAudioTracks` in MainScene.brs): switches to the best
  passthrough track (EAC3/Atmos → AC-3), skips TrueHD/DTS-HD/commentary. **Needs
  a sideload + replay of ROTS to verify** (read `/cast/log`). If audio is fixed
  but it still stutters, next suspect is throughput (~90 Mbps 4K REMUX; check the
  Roku is wired, not Wi‑Fi).
- **RT logos:** rotten/certified re-encoded to transparent RGBA + versioned
  filenames (`rt_rotten1`/`rt_certified1`) to bust Roku's image cache.
- **Direction set:** after the Roku audio verify, dev shifts to **phone + ELKO**
  native renderer as a couch appliance (auto-launch TV mode + phone-as-remote for
  lossless from the couch), plus **XInput/Xbox controller** support as a remote.
- **Roku transcode path rejected:** transcoding video to fit the slow link =
  "Plex 2.0"; killed the idea (see memory `never-transcode-no-plex-2.0`). The
  Roku stays a **direct-play-only** fallback (its link is the real bottleneck:
  ~90 Mbps via a Wi-Fi-backhauled repeater vs a ~128 Mbps REMUX peak).
- **Desktop carousel home built:** rebuilt `library_screen` off `/api/home` —
  featured hero (clearlogo + IMDb/RT/Metacritic chips + Play, auto-advancing
  with arrows/dots) over horizontal rails. New `screens/home_widgets.dart`,
  `getHome()`, `HomeData`/`HomeRail` models, `Movie` extended with ratings +
  logo/trailer. Web build deployed (served at `/`). Hero trailer autoplay = Phase 2.
- **Borderless fullscreen** on desktop: F11 + titlebar button via
  `window_manager` (conditional import — web gets a no-op stub).
- **Roku closed out:** verified every client-side path fails on the 4K DV TrueHD
  REMUX (TrueHD silent+freeze; EAC3 switch mid-stream = "malformed data",
  during-buffering = wedge; still underran post-mesh). Roku = fallback for
  lighter files only; logged to memory. Done chasing it.
- **v0.3.13+12 Windows build deployed to ELKO** (`C:\NASCinema\renderer` via C$,
  robocopy clean, app wasn't running). ELKO now has the carousel home +
  fullscreen. **Next: launch it on ELKO, test ROTS via the native renderer**
  (client=native → direct-play, TrueHD/Atmos to the Denon, DV to the C2 — the
  lossless payoff), then build phone-remote → ELKO + XInput.
- **BREAKTHROUGH — media_kit is out, native mpv is in.** media_kit's embedded
  Flutter player cannot render 4K HDR Dolby Vision on ELKO (Windows/ANGLE) — GPU
  mode fails the EGL surface, software mode never calls the render (black screen,
  both). Ruled out everything else (file/backend/decode/layout/logging). Native
  **mpv** (shinchiro build via winget, `C:\Program Files\MPV Player\mpv.exe`)
  plays the 52 GB 4K HDR DV TrueHD Atmos ROTS REMUX **flawlessly** — picture +
  **lossless Atmos to the Denon** (C2 Atmos popup too), no buffering. Flags:
  `--fullscreen --hwdec=auto --audio-spdif=truehd,dts-hd,eac3,ac3 --audio-exclusive=yes`.
  See memory `elko-renderer-is-native-mpv`. **Next: wire Play → launch mpv (URL +
  HDR + passthrough + `--input-ipc-server`) instead of the media_kit Video
  widget; app becomes browse-UI + remote; IPC drives pause/seek/stop.** Pin
  `--aid=1` for the lossless TrueHD track (not the lossy DD+ Atmos track).

---

## The one thing that must not be lost again

NASCinema's flagship is the **native `media_kit`/libmpv player on the
TV-wired PC (ELKO)** — direct-play the REMUX (no transcode), **bitstream
TrueHD/Atmos to the Denon**, pass **HDR** to the LG C2, render **PGS/ASS/SRT
subs natively (no burn-in)**, driven by the **phone as a remote**
("Play on \<renderer\>").

**The browser/web app is the FALLBACK** (phones, remote, "when the PC is off").
A browser physically cannot bitstream TrueHD/Atmos or render PGS. Everything
built so far is mostly the *fallback path*; the flagship native renderer is the
still-unbuilt keystone (Phase 1, unchecked).

> We drifted into browser-first because it was the quick debug harness, then
> kept polishing it. Don't keep shining the fallback — build the keystone.

---

## What's actually built and working

**Backend** (FastAPI + Socket.IO + async SQLAlchemy 2.0 + psycopg3 + PostgreSQL 17,
Python 3.14, runs on **ALPINE**; `/api/health` → `db:true`):
- Scanner (guessit + **ffprobe at scan**: container/codecs/resolution/bit-depth/HDR), TMDB metadata, browse API.
- **Playback decision engine** (Direct Play → Remux → Transcode) + live **"why am I transcoding?" badge** — a genuine differentiator, and on-vision.
- HLS transcode: **GPU NVENC + libplacebo HDR→SDR tonemap**, CPU x264 fallback; config-driven (`NASCINEMA_TRANSCODE_HWACCEL`).
- **Persistent transcode cache** on the NAS (LRU eviction at a GiB cap, smart-seek restart, orphan-PID reaping, scandir + `to_thread` for SMB).
- **OpenSubtitles → WebVTT** (search by hash then title/year, download, convert, cached) + **per-file sync offset**.

**Frontend** (Flutter; web is the only fully-wired client so far, windows/android scaffolded):
- Theme, models, library poster grid, movie detail page, server-config screen, API client — **all client-agnostic, reused by the native player**.
- Web player: hls.js glue + custom scrubber + controls + subtitle menu + sync bar.
- **Important seam:** [player_view.dart](frontend/lib/screens/player/player_view.dart) conditionally exports `native` (default) vs `web` (`dart.library.js_interop`). [player_view_native.dart](frontend/lib/screens/player/player_view_native.dart) now **fills the seam with media_kit/libmpv** (was the empty stub); the browser player stays as the fallback leg.

### New this session (2026-06-25) — code-complete + compiles, NOT yet hardware-verified
- **Native ELKO renderer** ([player_view_native.dart](frontend/lib/screens/player/player_view_native.dart)) — all ~16 seam accessors on a libmpv `Player`: direct-play `/api/stream/{id}/direct`, native subtitle tracks, sub-offset via mpv `sub-delay`, keyboard parity, proper teardown. **Audio passthrough wired** (`audio-exclusive=yes` + `audio-spdif=ac3,dts,eac3,truehd,dts-hd,dts-hd-ma`). `flutter build windows` is **green on ALPINE** (libmpv + media_kit DLLs link); app launches without crashing. **Unproven on real hardware:** TrueHD/Atmos bitstream to the Denon, and **HDR to the C2** — media_kit renders into a Flutter texture (not direct-to-display), so HDR passthrough may need `vo=gpu-next`/a separate libmpv window. Validate on ELKO.
- **Chromecast** — web sender, default media receiver. CAF SDK + glue in [web/index.html](frontend/web/index.html), [cast.dart](frontend/lib/services/cast.dart) (web/stub conditional export), cast button in [player_screen.dart](frontend/lib/screens/player_screen.dart). Rides the existing HLS+VTT fallback pipeline (Chromecast is fallback-class — no bitstream/PGS). **Untested functionally** — needs a real Chromecast + Chrome on the LAN (no APK; it's a *web* sender).

### New this session (2026-06-28) — branded Cast receiver WORKING on hardware ✅
- **Casting to the branded NASCinema receiver now plays video+audio on the LG C2.** Confirmed live by Matt. Phone (pure-Dart CASTV2 sender) → custom CAF receiver (App ID **4D655A07**, hosted at `https://nascinema.simpson1045.com/cast/receiver.html`).
- **Root cause of the long "audio but no video / stuck on Ready-to-cast" hunt:** the receiver JS was **throwing during init** — `pm.addEventListener(cast.framework.events.EventType.PLAYER_STATE_CHANGED, …)` where **`PLAYER_STATE_CHANGED` is `undefined` in this CAF v3 SDK**. The throw aborted init *before* `context.start()`, so the receiver never registered its LOAD handler. Diagnosed via an on-screen + backend-POSTed debug log (see below).
- **Fixes (all in [backend/cast/receiver.js](backend/cast/receiver.js), served live — NO app build needed):**
  - Init wrapped in try/catch with step markers; global `window.onerror`/`unhandledrejection` → log.
  - Defensive `on(type,label,fn)` listener registration — skips an undefined EventType instead of crashing.
  - Replaced the nonexistent `PLAYER_STATE_CHANGED` with the real media events: **`MEDIA_STATUS` / `PLAYING` / `PAUSE` / `ENDED`** (all confirmed present), plus `setState(PLAYING)` in the LOAD interceptor so the opaque idle screen drops immediately and stops covering the video.
  - `setState` logging de-duped; on-screen `#debug` box hidden by default (`body.debug` to re-enable). Receiver cache-bust now at **`?v=9`**.
- **Debug pipe (kept, useful):** `POST/GET/DELETE /cast/log` in [backend/app/main.py](backend/app/main.py) (in-memory deque, registered before the `/cast` static mount). The receiver POSTs every debug line; pull with `GET https://nascinema.simpson1045.com/cast/log`. On-screen box hidden by default (`body.debug` to re-enable).

#### Everything that then shipped (all confirmed on hardware), current = **0.3.12+8**, receiver **?v=15**
- **App changes (built, in 0.3.12):** prefer the custom receiver with Default-Media-Receiver fallback + a LOAD retry; phone sends `client='web'` (honest transcode badge); home-screen cast button; the movie-detail **Play banner casts straight to the TV when already connected** (shared [cast_actions.dart](frontend/lib/services/cast_actions.dart)); **rejoin-on-resume** ([cast_controller_native.dart](frontend/lib/services/cast_controller_native.dart) is now a `WidgetsBindingObserver` — remembers the last device, reconnects to the running receiver on app resume; LAUNCH for an already-running app rejoins without restarting playback).
- **Fully custom receiver (no default Cast chrome):** swapped `<cast-media-player>` for a plain `<video>` (CAF binds to it) and `display:none` the SDK-injected `<touch-controls>`. On pause: real paused frame + bottom gradient (no blurred wallpaper). Clock only on the idle screen. Subtitle style matches the web player (transparent box, white text, black outline) via `req.media.textTrackStyle`.
- **Clearlogo:** [metadata.py](backend/app/metadata.py) `get_movie_logo()` pulls the TMDB clearlogo (cached per process); [stream.py](backend/app/api/stream.py) play decision returns it; receiver shows it upper-left on pause (JF-style), text-title fallback. Backend+receiver only — no app build.
- **Backend hang under cast-transcode load = FIXED:** `_use_nvenc()` shelled out an ffmpeg probe (up to 25s) on every transcode start/seek-restart *under the global `_lock`*; now cached (`_nvenc_probe()` with `@_lru_cache`).
- **Versioning gotcha (now in memory):** `+BUILD` = Android `versionCode`; it must only ever go UP. Cutting 0.3.12 as `+1` (< shipped `+5`) caused "App not installed"; fixed by going to `+6`, then `+7`, `+8`. Next build is `+9`.
- **Open follow-ups:** transcode-path casting works but isn't heavily tested; subtitle track list isn't re-fetched after a rejoin (transport controls do work).
- **Backend restart recipe (ALPINE, run_command):** processes are `nascinema_run.py` under `D:\Programming\NASCinema` on port **8400** (two PIDs: launcher + uvicorn worker). `Stop-Process` both, then `Start-Process … python.exe nascinema_run.py -WorkingDirectory D:\Programming\NASCinema\backend -WindowStyle Hidden` (detached; NASCinema is **not** auto-supervised). Receiver/backend edits are server-side & live; **app** changes need `backend\release.bat <ver> <build>` (build must exceed the last shipped).

### New this session (2026-06-29) — native Roku channel browsing on hardware ✅ + NAS recovery
- **VISION REFRAME (now in memory [[vision-native-renderer-is-flagship]]):** the flagship is the **native Roku channel** on the **Roku Ultra 4802X** — Roku passes **Dolby Vision + TrueHD/Atmos** through to the Denon/C2 natively, which is the whole "install an app on the TV, direct-play the file, let the home theater do the work" dream. The ELKO native PC renderer **and** the browser/cast paths are now both *fallbacks*. (Fire TV/Android TV/webOS/tvOS all rejected — see memory.)
- **Roku channel scaffolded + running** (BrightScript/SceneGraph) under [roku/](roku/): `manifest`, `source/main.brs`, `components/{MainScene,MoviePoster,HttpTask}.{xml,brs}`. Talks to the backend at `m.base = http://192.168.0.150:8400`. Sideload via `http://192.168.0.78` (rokudev; IP reserved in router). Debug = POST to `/cast/log` (`logmsg`), no telnet needed.
- **Home is now a server-driven carousel ✅** — `/api/home` composes ranked rails (Continue Watching, Popular, Recently Added, Top Rated, 8 genre rails) and the Roku renders them in a `RowList` of `MoviePoster` tiles. **Two brutal SceneGraph gotchas, both now fixed + commented in code:** (1) array-typed fields (`rowItemSize` etc.) parse to garbage as XML attribute strings — set them in BrightScript; (2) **`RowList` needs `itemSize` set** (the list's overall width × row height) or it collapses to ~44px wide and silently renders **zero** tiles while still drawing a focus box. Diagnosed by reading the device console over **telnet 8085** (`scripts`-style capture from FRAMEWORK via `python` socket + ECP `launch/dev`) — not by guessing. The old single `MarkupGrid` (also needed `itemSize`+`itemComponentName`) is retired; that tile component is reused in the rails.
- **Ratings/popularity backend ✅** — `Movie` gained `popularity`, `vote_count`, `imdb_id`, `imdb_rating`, `rt_score`, `metacritic`, `collection_id/name` (migration **0007**). TMDB capture grabs popularity/votes/imdb_id/collection free from the details call; **OMDb** (`omdbapi.com`, key in `.env`, verified live) adds IMDB/RT/Metacritic. `/api/backfill-ratings` populated 206 movies. Google ratings dropped (no clean API).
- **NEXT: featured hero block** — a full-bleed auto-advancing top hero (backdrop + clearlogo + badges) above the rails, NASRadio-style. Decision: play **real trailers** via **yt-dlp** (reuse the NASRadio wiring) — backend downloads/caches the TMDB trailer (YouTube) as MP4 and serves it, since Roku can't stream YouTube directly. Backend (trailer cache + featured endpoint) first, then the `FeaturedHero` SceneGraph component + hero↔rails focus management.
- **Direct-play wired but NOT yet working at 4K** — `Video` node + `/api/stream/{id}/direct`, `streamFormat` from container (`mkv` for matroska). **Open bug (deferred):** 4K TrueHD title plays ~10s then **freezes with no audio** (state flapping playing↔paused). Suspect throughput vs. TrueHD-over-channel; instrumentation (pos/bitrate/underrun) added in `onVideoState`. Diagnose AFTER the NAS library copy finishes (a 4K direct-stream now would fight the copy for NAS read bandwidth and pollute the result).
- **NAS hardware scare → recovered.** A volume2 NVMe (Samsung 990) died, then its mirror thermal-dropped; a cool-down reboot brought both back. Docker stack (Vaultwarden/NPM/etc.) was safe on volume1 the whole time. The movie library was **consolidated to a single clean `/volume1/Totally Legal Movies` (deduped)**; the "Totally Legal Movies" SMB share was re-registered onto volume1. `NASCINEMA_MEDIA_DIRS` repointed to the **LAN IP** `\\192.168.0.248\Totally Legal Movies` (the `NorthsideNAS` hostname → Tailscale, slow). **PENDING:** a D:→NAS copy is bringing the NAS to ~208 movies; **one** clean rescan (add+prune) is on hold until that copy lands, then the backend restarts to pick up the new path. Decision: NAS = the single complete library; D: is NOT a second `MEDIA_DIRS` root (it gets mirrored as backup instead).

### On-vision vs fallback-only (so nothing gets re-polished by mistake)
- **Spine, reused everywhere:** scanner, probe data, TMDB, schema, browse API, decision engine + "why" badge, OpenSubtitles download, the Flutter shell.
- **Fallback-only (valid, but for phones/TV-browser/remote — not ELKO):** HLS transcode, GPU NVENC, HDR tonemap, NAS cache, smart seek, the WebVTT pipeline, and the browser-specific player glue ([player_view_web.dart](frontend/lib/screens/player/player_view_web.dart), hls.js / `::cue` / cue-shift / unmute hacks in [web/index.html](frontend/web/index.html), service-worker handling).

---

## Next work: get the native renderer ONTO ELKO and prove it (Phase 1 keystone)

The seam is filled and compiles; the remaining work is **hardware verification on
ELKO** (the PC wired to the C2 + Denon):
- **Build host = ALPINE.** `Y:` is ALPINE's `D:`, so the live tree is on ALPINE's
  local disk (Windows 11 + Flutter + VS C++). Build via the MCP `run_command`
  connector: `cd D:\Programming\NASCinema\frontend; flutter build windows --release`.
  (`flutter build windows` **fails on the NAS share** — plugin symlinks; must be
  local disk. See [[windows-build-needs-local-disk]].)
- **Deploy to ELKO:** copy the `Release` build folder to ELKO's `C$` (reachable
  from the connector); **launch it on ELKO** — ELKO has no remote shell in the
  connector yet, only ALPINE does. Use `--release` (a Debug build needs the VS
  Debug CRT ELKO won't have).
- **Verify on the C2 + Denon:** direct-play (no transcode), TrueHD/Atmos bitstream,
  **HDR passthrough** (the open question above), native PGS/ASS/SRT subs.
- After that, the things with **no equivalent anywhere**: phone-as-remote → renderer handoff, and the **Extras DB** ([EXTRAS_DB.md](EXTRAS_DB.md)).

**Honest framing for "how is this different from Plex/JF?":** today, via the
browser, it largely isn't — we rebuilt their *web* experience. Even the native
renderer's raw capability isn't unique (JF + Kodi/mpv already direct-plays +
bitstreams + renders PGS). NASCinema's real edge is **execution/UX** (clean by
default, one Flutter codebase, phone→wired-PC renderer), **no paywall/phone-home**,
the **Extras DB**, and the **cinema-experience soul**. Almost all of it is still ahead.

---

## Environment & gotchas (verified this session)

- **Machine topology:** ALPINE = server (backend/PG17/ffmpeg); FRAMEWORK = dev box; **ELKO = renderer** (TV-wired PC → C2 + Denon); NAS = storage only. Run backend commands on ALPINE.
- **NAS access uses the LAN IP `192.168.0.248`, NOT the `NorthsideNAS` hostname** (it resolves to a Tailscale IP → SMB tunnels → flaps between fast/direct and ~0.7 MB/s relayed; this caused inconsistent playback). `NASCINEMA_CACHE_DIR=//192.168.0.248/movie_cache` is pinned. **Still on the hostname:** `media_dirs` + stored `mf.path` source paths — transcoding *uncached* content reads source over Tailscale; pin it (media_dirs → IP + `UPDATE media_file SET path=replace(path,'NorthsideNAS','192.168.0.248')`) if that's slow.
- **Windows desktop build host is ALPINE, not the share.** `flutter build windows` can't create media_kit's plugin symlinks on the NAS share (`Y:` = `\\Desktop-alpine\d`); build from ALPINE's local `D:` via the connector (cold media_kit build > the connector's 120s cap → launch detached + poll). See [[windows-build-needs-local-disk]].
- `socketio.ASGIApp` does **not** forward ASGI lifespan to the wrapped FastAPI app → startup work (`startup_cleanup`) lives in `nascinema_run.py`, not the lifespan.
- Windows needs `SelectorEventLoopPolicy` for psycopg.
- Flutter web is built with `--pwa-strategy=none` (+ an unregister script in index.html) — the PWA service worker served stale caches on a constantly-rebuilt app.
- **Measurement traps:** PowerShell/.NET initializes its HTTP stack ~2s on the first request per process (ignore the first call); `Invoke-WebRequest` is slow on large binary bodies — use `System.Net.WebClient`/`File.ReadAllBytes`. Don't chase these as if they were server costs.

## Working rules (from memory)
- **Explain before altering code** — answer/propose in plain English, get a nod *before* editing/restarting/committing.
- **Verify, don't speculate** — measure the real cause or say "I don't know."
- **Versioning is earned** — `X.Y.Z+BUILD`: `+BUILD` = trivial; `Z` = regular fix/feature; `Y` = new feature/overhaul; `X` = remarkable v1.0. Default to the lower tier.
- **Multi-user & config-driven**, **deployment-topology-agnostic** — nothing hardcoded; all hosts/paths/keys/devices are config.
