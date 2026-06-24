# NASCinema

> Self-hosted movies & TV from your NAS — own your living room, not a subscription

[![Flutter](https://img.shields.io/badge/Flutter-Latest-blue.svg)](https://flutter.dev/)
[![Python](https://img.shields.io/badge/Python-3.14-blue.svg)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-async-009688.svg)](https://fastapi.tiangolo.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-blue.svg)](https://www.postgresql.org/)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-transcode-success.svg)](https://ffmpeg.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Status: 🎬 pre-v1.0 — in design / pre-alpha.** This README is the spec we're building toward, not a description of a finished app. The phased build plan lives in [ROADMAP.md](ROADMAP.md). NASCinema is **multi-user and fully config-driven from day one** — nothing is tied to one person's machine or storage (see [Design principles](#design-principles)).

NASCinema is the video sibling of [NASRadio](https://github.com/simpson1045/NASRadio) — a self-hosted movie & TV server that streams from your NAS to your desktop, phone, and living-room TV. It's built to fix the exact things that make Jellyfin frustrating and Plex expensive: **subtitles that actually load, direct play that actually direct-plays, remote access that doesn't cost a subscription, and one app that looks the same everywhere.**

It deliberately reuses NASRadio's proven backbone — authenticated API, scoped media tokens, pre-transcode cache, the 10-foot TV shell, Chromecast, in-app server config, and self-healing acquisition — and adds the video layer on top: TV-show hierarchy, a real subtitle pipeline, HDR handling, skip-intro, and a phone-as-remote living-room experience.

---

## Why NASCinema (vs. Plex & Jellyfin)

| Pain point | How NASCinema wins |
|---|---|
| **Transcoding / playback** | Every file is probed at scan. **Remux-first** (copy streams, ~0 CPU) before ever transcoding. A per-playback **"why am I transcoding?" badge** — the thing Plex/JF hide. Pre-transcoded HLS cache on the NAS for instant remote. |
| **Subtitles** | The desktop/mobile player (libmpv) renders **embedded MKV subs — PGS, ASS, SRT — natively with direct play, no burn-in.** Dumb clients get pre-extracted WebVTT sidecars; bitmap subs are **OCR'd to text once** and cached. Burn-in is the last resort, never the default. |
| **Remote access (the Plex paywall)** | Rides **your own** reverse proxy (e.g. Nginx Proxy Manager + CloudFlare) → HTTPS remote with **no subscription, no relay, no phone-home**. Expiring scoped **share links** to a single title. Per-user bandwidth caps. |
| **UI / apps** | One Flutter codebase → Windows, Android, **Android/Fire TV 10-foot shell**, iOS. Living-room control via **phone-as-remote → PC renderer**. Blurred-backdrop detail pages, global resume bar, Cast. |

---

## Design principles

Two rules sit above every feature in this repo:

### 1. Multi-user & config-driven — nothing hardcoded
NASCinema is built for **many users on one server**, not one person's setup. Therefore:
- **No host, path, port, credential, API key, or device name is ever baked into the code.** Every one of them is configuration.
- **Server-level settings** (media library paths, `DATABASE_URL`, integration keys, public URL) live in `.env` / an admin settings UI — set once per install.
- **Per-user settings** (preferred language, subtitle style & defaults, bandwidth cap, renderer devices, Trakt account, content-rating limits, theme) live in **that user's account** and travel with them across devices.
- A clean separation: *admin configures the server; each user configures their own experience.* If you ever feel tempted to type a literal hostname or path into a source file, it belongs in config instead.

### 2. Versioning is earned, not automatic
- We start **pre-v1.0** and stay there until NASCinema is genuinely remarkable. `v1.0.0` is a milestone, not a default.
- **Version numbers are reserved for real, shipped features or critical bug fixes.** One-line fixes, refactors, doc tweaks, and chores **do not** bump the version.
- Semantic-ish within 0.x: `0.MINOR.0` for a meaningful feature set, `0.x.PATCH` only for critical fixes. Everyday commits just land on `main` with no version change.

---

## Design identity

NASCinema is unmistakably part of the **NAS family** — same deep-navy cyberpunk base and frosted-glass grammar as NASRadio — but with its own **"Blockbuster cyberpunk"** accent so you know at a glance you're in the movies app, not the music app.

| Token | Value | Use |
|---|---|---|
| Background | `#0a0e27` | App canvas (shared with the family) |
| Surface | `#141a35` | Cards, sheets |
| Surface raised | `#1d2547` | Posters, inputs |
| **Accent (primary)** | **`#ffb020`** | Marquee amber — play buttons, active nav, badges |
| **Accent (secondary)** | **`#b46bff`** | Violet — avatars, TV badges, highlights |
| Text | `#eef1ff` | Primary text |
| Muted | `#8b93bf` | Secondary text |

Frosted-glass cards · blurred backdrop ambient glow · color-coded format badges (4K / HDR / 1080p) · global mini/resume player · 10-foot TV layout · A-Z quick scroll.

---

## Architecture

```
Flutter Frontend (Windows / Android / Fire TV / iOS)
    +-- media_kit (libmpv) — desktop & TV player: direct play, native MKV subs, HDR
    +-- video_player / native — mobile playback
    +-- http (REST API with retry helpers)
    +-- socket_io_client (scan progress, phone-as-remote, Watch Together)
         |
         | HTTPS + WSS via Nginx Proxy Manager + CloudFlare
         v
FastAPI Backend (Native Windows / Synology NAS)
    +-- async streaming (HTTP range, on-the-fly HLS segments)
    +-- PostgreSQL 17 (library, users, watch state, sub/codec probe cache)
    +-- itsdangerous signed tokens + scrypt hashing (ported from NASRadio)
    +-- Scoped read-only media tokens (stream/artwork/share links)
    +-- FFmpeg / FFprobe (probe, remux, transcode, HLS, trickplay, sub extract)
    +-- Subtitle pipeline (VTT extract, PGS/VOBSUB OCR, OpenSubtitles)
    +-- TMDB / Fanart / Trakt / OpenSubtitles integrations
    +-- Radarr / Sonarr / Prowlarr / Transmission (acquisition, self-healing)
    +-- \\<your-nas>\<your-share> media — configured per install, never hardcoded (SMB/NFS)
```

Sidecar services (optional, NAS-hosted like NASRadio): **PGS/VOBSUB OCR worker** and a **batch transcode/trickplay worker**.

---

## Tech stack

### Backend
| Component | Technology |
|---|---|
| Language | Python 3.14 (core backend; ML/audio sidecars may pin an older interpreter) |
| Framework | FastAPI (async) + Uvicorn |
| Database | PostgreSQL 17 |
| Auth | scrypt hashing + itsdangerous signed tokens (ported from NASRadio) |
| Media probe / transcode | FFmpeg + FFprobe |
| Subtitle OCR | Tesseract / pgsrip (bitmap → SRT) |
| Realtime | python-socketio (ASGI) |
| Metadata | TMDB, Fanart.tv, OMDb |
| Watch sync | Trakt |
| Subtitles | OpenSubtitles |
| Acquisition | Radarr, Sonarr, Prowlarr, Transmission |

### Frontend
| Component | Technology |
|---|---|
| Framework | Flutter (latest stable) |
| Language | Dart |
| Desktop / TV player | media_kit (libmpv) |
| Mobile player | video_player / platform native |
| HTTP | http |
| Realtime | socket_io_client |
| State | Provider + ChangeNotifier |
| Token storage | flutter_secure_storage |
| Cast | bonsoir (mDNS) + custom receiver |

### Infrastructure
| Component | Technology |
|---|---|
| Runtime | Native Windows or Linux (FastAPI/Uvicorn) |
| Database | PostgreSQL 17 |
| Storage | Any SMB/NFS-accessible NAS (Synology, TrueNAS, Unraid, …) |
| Reverse proxy | Any (e.g. Nginx Proxy Manager, Caddy, Traefik) |
| DNS | Any (e.g. CloudFlare) |

All infrastructure rows are **examples, not requirements** — every host, path, port, and key is set in config, never baked into the code.

---

## Subtitles, done right

Subtitles are NASCinema's flagship differentiator, because they're where Plex/JF hurt the most. There are two fundamentally different kinds:

- **Text subs** — SRT, ASS/SSA, mov_text. Strings + timecodes.
- **Bitmap subs** — **PGS** (Blu-ray `.sup`), VOBSUB (DVD). *Pictures* of text, with no text data.

Browsers and locked-down TV clients can only render **WebVTT** (text). So when Plex/JF meet a PGS track, their only fallback is to **burn it into the video** — forcing a full transcode and breaking direct play. NASCinema avoids that:

1. **Probe every track at scan** (ffprobe) → codec, language, forced/default flags stored per file.
2. **Native render where it counts** — the libmpv-based player on PC/phone draws PGS, ASS, and SRT as overlays **without re-encoding video**. Direct play stays intact.
3. **Pre-process for dumb clients, cached on the NAS** — text subs → WebVTT sidecar (instant); bitmap subs → **OCR to SRT** once, then treated as text forever.
4. **Burn-in is the last resort**, only when a client can do nothing else — and the player tells you *why*.

Plus: OpenSubtitles auto-download, per-file sync offset (remembered), forced/default track selection.

---

## How you watch (the living room)

Often the best video player you own is a **PC already wired to the TV**. Many smart-TV platforms (e.g. webOS, Roku) aren't sideload-friendly, so NASCinema flips the problem:

> **Browse on your phone → tap "Play on \<renderer\>" → it plays on the big screen.**
> Phone is the remote, the TV-connected PC is the renderer — Spotify-Connect style, over the same socket channel NASRadio uses for device handoff.

Renderers are **discovered, named, and saved per user** — no device is hardcoded. Best-in-class playback (direct play, native subs, HDR) with **zero sideloading**. Fallbacks for when the PC is off:
- **TV-browser web app** — open your NASCinema URL right in the smart-TV browser (HLS + VTT sidecars).
- **Roku channel** (later) — a thin HLS client.
- **webOS native app** (much later) — packaged Flutter web build via Dev Mode.

---

## Quick start

> ⏳ Coming with Milestone 1. Will mirror NASRadio's flow: configure `.env` (media paths, `DATABASE_URL`, TMDB key), create the first admin user, `python run.py --scan`, then point the Flutter app at your server from the login screen's gear icon. See [ROADMAP.md](ROADMAP.md) for current status.

---

## Roadmap

The full phased plan with checkboxes is in **[ROADMAP.md](ROADMAP.md)**. The short version:

1. **Foundation** — repo, theme, stack decisions ← *we are here*
2. **Movies MVP** — scan → TMDB → browse → direct-play/remux/transcode + "why" badge → remote
3. **Subtitles done right** — probe, native render, VTT/OCR sidecars, sync offset
4. **The living room** — phone-as-remote → PC renderer, Cast, C2 web app
5. **TV shows** — series/season/episode, watched state, next-episode autoplay, On Deck
6. **Discovery & personalization** — recommendations, smart collections, trickplay, Trakt, Year in Review
7. **Sharing & multi-user** — profiles, kids, share links, request system, Watch Together
8. **Acquisition** — Radarr / Sonarr / Prowlarr / Transmission
9. **The cinema experience** — Coming Attractions, Roulette, Art Mode, "Because it's raining," premieres
10. **Polish, ops & more clients** — transcode dashboard, health, auto-update, Roku, webOS

---

## License

MIT — see [LICENSE](LICENSE).

## Contact

Matt Hanington — part of the **NAS family** ([NASRadio](https://github.com/simpson1045/NASRadio))
