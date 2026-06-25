# NASCinema — Handoff (honest current state)

*Last updated: 2026-06-25. This is the truthful state of the project for the next
session. The vision and full plan live in [README.md](README.md) and
[ROADMAP.md](ROADMAP.md) — **read those first**; this file is just "where we
actually are and what's next." Current version: **v0.3.7**.*

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
- `socketio.ASGIApp` does **not** forward ASGI lifespan to the wrapped FastAPI app → startup work (`startup_cleanup`) lives in `run.py`, not the lifespan.
- Windows needs `SelectorEventLoopPolicy` for psycopg.
- Flutter web is built with `--pwa-strategy=none` (+ an unregister script in index.html) — the PWA service worker served stale caches on a constantly-rebuilt app.
- **Measurement traps:** PowerShell/.NET initializes its HTTP stack ~2s on the first request per process (ignore the first call); `Invoke-WebRequest` is slow on large binary bodies — use `System.Net.WebClient`/`File.ReadAllBytes`. Don't chase these as if they were server costs.

## Working rules (from memory)
- **Explain before altering code** — answer/propose in plain English, get a nod *before* editing/restarting/committing.
- **Verify, don't speculate** — measure the real cause or say "I don't know."
- **Versioning is earned** — `X.Y.Z+BUILD`: `+BUILD` = trivial; `Z` = regular fix/feature; `Y` = new feature/overhaul; `X` = remarkable v1.0. Default to the lower tier.
- **Multi-user & config-driven**, **deployment-topology-agnostic** — nothing hardcoded; all hosts/paths/keys/devices are config.
