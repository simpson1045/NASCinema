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
- [x] FFmpeg/FFprobe confirmed (auto-discovered on ALPINE; `/api/health` reports both available)
- [x] **Config model** — `pydantic-settings` (`NASCINEMA_` env), ffmpeg auto-discovery, `.env` with generated secret key; zero hardcoded paths/hosts/keys/devices
- [x] **Backend scaffold** — FastAPI + Socket.IO, async SQLAlchemy 2.0 + Alembic (`0001` users), auth (scrypt + itsdangerous + scoped media tokens), `run.py`; **boots on ALPINE, `/api/health` → `db:true`** 🔁
- [x] First admin user CLI (`manage_users.py` create/list/passwd) 🔁
- [x] Create the first admin account (`simpson1045`, admin)
- [x] Frontend scaffold — Flutter shell (Windows + Android) + amber/violet theme; ConnectScreen does a live `/api/health` check (analyze + test green)
- [ ] **Per-user settings store** — language, subtitle prefs, bandwidth cap, renderer devices, theme, integration accounts 🟡

---

## Phase 1 — Movies MVP (the spine) ⭐

The end-to-end vertical slice: a movie on disk becomes a playable, good-looking entry on the TV.

> 🎉 **v0.1.0 (2026-06-24)** — first browsable library is live: **354 movies** scanned from the NAS with TMDB artwork + ffprobe metadata, served as a Flutter web poster grid in the browser. Ingestion spine complete; playback is next.
>
> 🎬 **v0.2.0 (2026-06-24)** — **it streams.** Decision engine (Direct Play / Remux / Transcode) with a live "why am I transcoding?" banner; ffmpeg→HLS transcode with a full-runtime VOD playlist; self-hosted hls.js web player. 4K HEVC/HDR/TrueHD plays in the browser.

- [x] **Scanner** — walk media dirs, parse filenames (guessit), skip NAS junk, per-file commit
- [x] **FFprobe at scan** — store container/codecs/resolution/bit-depth/HDR per file
- [x] **TMDB metadata** — match by title+year, pull overview/poster/backdrop/rating/runtime/genres + match-confidence
- [ ] **Manual match override that survives rescans** ⭐ (the thing JF nukes) 🟡 🔁
- [ ] **Low-confidence review queue** for fuzzy matches 🟡 🔁
- [ ] **Artwork picker** — choose poster/backdrop/logo from TMDB/Fanart 🟢 🔁
- [x] **PostgreSQL schema** — movies, media_files, users (watch_state/tokens still to come)
- [x] **Flutter: library poster grid** — TMDB artwork, amber quality badges (4K/HDR/1080p), fallback tiles, pull-to-refresh
- [x] **Browse API** — `GET /api/movies`, `GET /api/movies/{id}`, `POST /api/scan`
- [x] **Web delivery** — backend serves the built Flutter web app at `/` (zero client tooling)
- [x] **In-app server config** (address field, persisted, auto-fills page origin on web)
- [x] **Flutter: movie detail page** — ambient backdrop, overview, genres, quality chips, file/quality + bonus-features sections, Blu-ray.com link
- [x] **Playback decision engine** — Direct Play → Remux → Transcode with a per-stream reason ⭐
- [x] **"Why am I transcoding?" badge** — shown live on the player ⭐
- [x] **HLS transcode/remux + range serve** — ffmpeg→HLS, uniform-segment VOD playlist (real runtime), self-hosted hls.js web player
- [ ] **Native player** (media_kit/libmpv) — direct-play 4K + resume 🟡 🔁
- [ ] **Smart seek** — restart transcode at the seek point (forward seek currently waits) 🟡
- [ ] **Watch progress / resume** + watched/unwatched state 🟢
- [ ] **Auth + scoped media tokens** wired into the endpoints 🔁
- [ ] **Remote access** verified through a reverse proxy (HTTPS) 🟢 🔁

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
- [ ] **In-player audio + subtitle track switching** 🟡
- [ ] **Whisper auto-generated subtitles** for content with none — speech-to-text + alignment (Whisper, not Essentia — Essentia is audio-features, not speech) ⭐ 🔴

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

### Player experience
- [x] **Unmute prompt** — muted autoplay + a tap-to-unmute banner (browser autoplay constraint)
- [ ] **Custom player controls** — Flutter overlay replacing native HTML5 → unlocks everything below 🟡
- [ ] **Trickplay thumbnails** — frame previews on the scrubber (the video-native "waveform"); optional subtle audio waveform for family flavor 🟡 🔁
- [ ] **Actor popups** — tap a cast member mid-playback for info (TMDB cast) 🟡
- [ ] **"Did You Know" facts** — trivia cards during playback (TMDB/IMDb) 🟢
- [ ] **Paused clearlogo** — movie logo in the corner when paused, Jellyfin-style (Fanart.tv/TMDB) 🟢
- [ ] **Stats for nerds** — "More Info" overlay: codecs, bitrate, transcode/decode path, buffer health 🟢

---

## Phase 10 — Polish, ops & health

- [ ] **Transcode / HW-accel dashboard** — what's transcoding, why, on which encoder 🟢 🔁
- [ ] **Storage & library health** — disk space, orphans, failed scans 🟢
- [ ] **In-app auto-update** system 🟡 🔁
- [ ] **Backup** of DB + metadata/artwork 🟢 🔁
- [ ] System log viewer with service health 🟢 🔁
- [ ] `.nfo` / local-artwork import (preserve Plex/JF work on migration) 🟡

---

## 🌐 Flagship initiative — Extras DB (crowdsourced special-features database)

The big swing: **"AcoustID/MusicBrainz for movie bonus features"** — a fingerprint-keyed,
crowdsourced database that finally names disc extras, exposed via API. Nobody has built
this; every ripper wants it. Full design in **[EXTRAS_DB.md](EXTRAS_DB.md)**.

- [ ] **Groundwork (now)** — Chromaprint fingerprint each extra + opt-in `NASCINEMA_CONTRIBUTE_EXTRAS`; store locally so we bank data from day one 🟡 ⭐
- [ ] Central service MVP — submit + lookup API, fingerprint clustering, consensus 🔴
- [ ] Auto-naming — batch fingerprint lookup on scan; auto-apply high-confidence, suggest the rest 🟡
- [ ] Community front-end — contributor accounts, moderation, public API 🔴

> Sequenced **after** NASCinema's core grows the user base (the DB's fuel is users), but
> collection starts now. The flywheel: more users → more mappings → better auto-naming.

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
