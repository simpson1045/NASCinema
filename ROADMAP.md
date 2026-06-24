# NASCinema — Roadmap

The working checklist. Phases are roughly sequential, but the fun stuff gets **sprinkled in as we go** — nothing here is locked to a hard order.

**Legend:** 🔁 reuses NASRadio infra · 🎬 cinema-experience delighter · ⭐ high-impact / switch-off-Plex feature
**Effort:** 🟢 small · 🟡 medium · 🔴 large

> **Cross-cutting principles (apply to every box below):**
> 1. **Multi-user & config-driven.** No host/path/port/key/device name in code — ever. Server settings → `.env`/admin UI; per-user settings → the user's account. Every feature is built for many users on one server.
> 2. **Versioning is earned.** Start pre-v1.0; bump only for real features or critical fixes; `v1.0.0` ships only when NASCinema is truly remarkable. One-liners don't move the number.

---

## Phase 0 — Foundation ← *we are here*

- [x] Study the NAS family DNA (NASRadio stack, theme, conventions)
- [x] Lock design identity — **Blockbuster cyberpunk**: navy `#0a0e27` base, amber `#ffb020` + violet `#b46bff` accents
- [x] Decide stack — **FastAPI** (async, video-friendly) + PostgreSQL, porting NASRadio's auth/token/transcode-cache concepts
- [x] Decide code-sharing — standalone now, extract a shared `nas-core` later (YAGNI)
- [x] Write README + ROADMAP (this doc)
- [x] Lock principles — multi-user & config-driven (nothing hardcoded), versioning is earned (start pre-v1.0)
- [x] Target runtime: **Python 3.14** for the core backend (full binary-wheel support verified for FastAPI/psycopg/pydantic/uvicorn); ML/audio sidecars pin their own interpreter
- [ ] Confirm FFmpeg/FFprobe on PATH (installed via winget ✅)
- [ ] **Config model** — server settings via `.env`/admin UI, per-user settings in account; zero hardcoded paths/hosts/keys/devices ⭐
- [ ] Repo scaffold: `backend/` (FastAPI app, `run.py`, `.env.example`) + `frontend/` (Flutter shell)
- [ ] Flutter theme — encode the amber/violet token set
- [ ] First admin user CLI (`manage_users.py`) + scrypt + itsdangerous tokens 🔁
- [ ] **Per-user settings store** — language, subtitle prefs, bandwidth cap, renderer devices, theme, integration accounts 🟡

---

## Phase 1 — Movies MVP (the spine) ⭐

The end-to-end vertical slice: a movie on disk becomes a playable, good-looking entry on the TV.

- [ ] **Scanner** — walk media dirs, parse filenames (guessit), detect movies 🟡
- [ ] **FFprobe at scan** — store codec/profile/level/bit-depth/resolution/audio layout/sub tracks per file 🟡
- [ ] **TMDB metadata** — match by title+year, pull overview/poster/backdrop/logo/cast/rating 🟡
- [ ] **Manual match override that survives rescans** ⭐ (the thing JF nukes) 🟡 🔁
- [ ] **Low-confidence review queue** for fuzzy matches 🟡 🔁
- [ ] **Artwork picker** — choose poster/backdrop/logo from TMDB/Fanart 🟢 🔁
- [ ] **PostgreSQL schema** — movies, files, users, watch_state, tokens
- [ ] **Auth + scoped media tokens** — signed bearer for API, read-only token for stream/artwork 🔁
- [ ] **Playback decision engine** — Direct Play → **Remux** (copy streams) → Transcode, in that order 🔴 ⭐
- [ ] **"Why am I transcoding?" badge** — surface the reason to the user ⭐ 🟢
- [ ] **HLS transcode + pre-transcode cache on the NAS** 🔴 🔁
- [ ] **HTTP range / direct-play serving** for compatible files 🟡
- [ ] **Flutter: library grid + movie detail** (blurred backdrop, meta, format badges) 🟡
- [ ] **Flutter: player** (media_kit/libmpv) with resume 🟡 🔁
- [ ] **Watch progress / resume** + watched/unwatched state 🟢
- [ ] **Remote access** verified through Nginx Proxy Manager + CloudFlare 🟢 🔁
- [ ] **In-app server config** (login-screen gear, no recompile) 🟢 🔁

---

## Phase 2 — Subtitles, done right ⭐

The flagship differentiator. (Full design in [README](README.md#subtitles-done-right).)

- [ ] Subtitle track inventory from the scan-time probe 🟢
- [ ] **Native render of embedded MKV subs** (PGS/ASS/SRT) via libmpv — no burn-in ⭐ 🟡
- [ ] **Text sub → WebVTT sidecar** extraction, cached 🟢
- [ ] **ASS styling preserved** (libass / JASSUB on web clients) 🟡
- [ ] **Bitmap sub (PGS/VOBSUB) → OCR to SRT** background worker, cached forever ⭐ 🔴
- [ ] **Burn-in path** as last resort, with the "why" badge 🟡
- [ ] **OpenSubtitles** search + auto-download (hash-matched) 🟡
- [ ] **Per-file sync offset** (+/- ms), remembered 🟢
- [ ] Forced / default / language track selection 🟢

---

## Phase 3 — The living room ⭐

- [ ] **Phone-as-remote → PC renderer** ("Play on \<renderer\>" — devices discovered & named per user, never hardcoded) over socket.io ⭐ 🔴 🔁
- [ ] **10-foot "couch mode"** UI on desktop (reuse Fire-TV shell) 🟡 🔁
- [ ] Device picker + handoff (pause here, resume there) 🟡 🔁
- [ ] **Chromecast** receiver for video (reuse NASRadio receiver) 🟡 🔁
- [ ] **C2 web app** — HLS + VTT in the TV browser, no sideload 🟢
- [ ] Gamepad / air-mouse navigation in couch mode 🟢
- [ ] Roku private HLS channel 🔴 *(later)*
- [ ] webOS native app via Dev Mode 🔴 *(much later)*

---

## Phase 4 — TV shows

- [ ] Series → season → episode model + scanner 🔴
- [ ] Per-episode watched state + progress 🟢
- [ ] **Auto-play next episode** + "still watching?" 🟢 ⭐
- [ ] **On Deck / Up Next** rows 🟢
- [ ] Season packs, special-episode handling, absolute ordering 🟡
- [ ] Default audio/sub track remembered per show 🟢

---

## Phase 5 — Discovery & personalization

- [ ] **Recommendations** — "More like this" / "Because you watched" 🟡 🔁
- [ ] **Trakt sync** — scrobble watches, sync watchlist/ratings from Letterboxd/IMDb/Trakt ⭐ 🟡 🔁
- [ ] **Smart / dynamic collections** — "4K HDR unwatched," "under 90 min," "leaving soon" 🟡
- [ ] **Trickplay** — sprite thumbnails on the seek bar, generated at scan 🟡 🔁
- [ ] **Year in Review** — personal "Wrapped" for movies 🟢 🔁
- [ ] **Cast & crew pages** — filmography, "in your library" 🟡
- [ ] **Franchise/saga ordering** — chronological vs release toggle 🟢
- [ ] **Mood / vibe tags** — "mind-bending," "cozy," "rainy day" (TMDB keywords) 🟢
- [ ] **Coming Soon / What's New** wall from TMDB 🟢 🔁
- [ ] **Duplicate / version finder** + "missing from collection" 🟡 🔁
- [ ] Per-user ratings, thumbs, personal notes 🟢

---

## Phase 6 — Sharing & multi-user

- [ ] **Profiles** — per-person history, avatars, watchlists 🟡 🔁
- [ ] **Kids profiles** with content-rating caps 🟡
- [ ] **Expiring share links** to a single title 🟢 🔁
- [ ] **Request system (Overseerr-style)** — request → fires Radarr/Sonarr → notify when ready ⭐ 🔴
- [ ] **Per-user bandwidth / quality caps** 🟡
- [ ] **Watch Together / SyncPlay** across households + reactions 🔴 🔁
- [ ] In-app admin user management 🟢 🔁

---

## Phase 7 — Acquisition pipeline 🔁

The movie/TV twins of NASRadio's Lidarr/Prowlarr/Transmission setup.

- [ ] **Radarr** (movies) + **Sonarr** (TV) integration 🟡
- [ ] **Prowlarr** search for missing titles 🟢 🔁
- [ ] **Transmission** add + **self-healing auto-restart** over SSH 🟡 🔁
- [ ] Import queue + review-before-add (with artwork picker) 🟡 🔁
- [ ] Auto-process on import — probe, trickplay, sub extraction/OCR 🟡

---

## Phase 8 — The cinema experience 🎬

The soul of the app — what makes it NASCinema and not a sterile grid.

- [ ] **Coming Attractions** — play real trailers before the feature ⭐ 🎬 🟡
- [ ] **Movie Night Roulette / "Surprise Me"** — one button picks by mood/runtime ⭐ 🎬 🟢
- [ ] **Art Mode screensaver** — cycle backdrops + logos when idle 🎬 🟢
- [ ] **"Because it's raining" rows** — tie into NASRadio's NWS weather ⭐ 🎬 🟡 🔁
- [ ] **Scheduled premieres** — "Dune plays at 8pm Friday" 🎬 🟡
- [ ] **Lobby ambiance** — subtle theme music on the home screen (toggle) 🎬 🟢
- [ ] Now-playing ambient blurred backdrop 🟢 🔁

---

## Phase 9 — Advanced playback

- [ ] **Skip Intro / Recap / Credits** via fingerprinting ⭐ 🟡 🔁 (Essentia)
- [ ] **HDR → SDR tone-mapping** for dumb clients 🟡
- [ ] **Multi-version picker** — same title in 4K HDR + 1080p 🟡
- [ ] **Offline downloads** on mobile 🟡
- [ ] Hardware-accel transcode (NVENC/QSV/VAAPI) detection + use 🟡

---

## Phase 10 — Polish, ops & health

- [ ] **Transcode / HW-accel dashboard** — what's transcoding, why, on which encoder 🟢 🔁
- [ ] **Storage & library health** — disk space, orphans, failed scans 🟢
- [ ] **In-app auto-update** system 🟡 🔁
- [ ] **Backup** of DB + metadata/artwork 🟢 🔁
- [ ] System log viewer with service health 🟢 🔁
- [ ] `.nfo` / local-artwork import (preserve Plex/JF work on migration) 🟡

---

## Backlog / someday

- [ ] Live TV / DVR (HDHomeRun)
- [ ] Clip sharing — timestamped link to a scene
- [ ] Co-watching chat / reactions overlay
- [ ] iOS + tvOS native clients
- [ ] Multi-NAS / multi-library federation
- [ ] Extract shared **`nas-core`** package (auth, tokens, transcode-cache, TV shell) once duplication with NASRadio is real

---

*Sprinkle liberally. Ship the spine first, then make it magic.* 🍿
