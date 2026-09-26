# NASCinema — Handoff (honest current state)

*Last updated: 2026-09-25. This is the truthful state of the project for the next
session. The vision and full plan live in [README.md](README.md) and
[ROADMAP.md](ROADMAP.md) — **read those first**; this file is just "where we
actually are and what's next." Current version: **v0.6.0+26 (Apple trailers + HDR) — see Latest; ELKO on 0.5.5+, Roku channel 0.1.7.*

---

## Latest (2026-09-25, late night) — Apple TV trailers + HDR (0.6.0, Roku 0.1.8)

- **Apple TV is the first trailer source** (`backend/app/apple_trailers.py`):
  TMDB → Wikidata P9586 → tv.apple.com uts catalog → HLS master → ffmpeg copy.
  Main `<id>.mkv` = HDR10/HDR10+ when offered (else best SDR), `<id>.sdr.mkv`
  = SDR copy for HDR titles. `GET /api/movies/{id}/trailer` serves SDR by
  default, `?variant=hdr` the master. Settings: `trailer_region`,
  `trailer_locale`, `apple_trailers`. Order in ensure_trailer: pin → Apple →
  YouTube → backdrop. Source JSON: `GET /api/movies/{id}/trailer/source`.
- **Library upgrade job** `POST /api/trailers/apple-upgrade?replace_pins=true`
  started ~04:15 UTC Sept 26 (poll GET). Downloads beside current trailer,
  swaps only on success; clears a pin only when Apple replaced it (list in
  the GET response `unpinned`). Runs inside the backend process — a restart
  kills it; re-POST resumes (skips "already").
- **Pins before the upgrade** (restore by PATCH trailer_youtube if wanted):
  56 BHC3 BhfZMtv9XuE · 97 Grown Ups 1m-NrYetgOU · 100 Chamber oQtgBqXMgv0 ·
  106 Sorcerer's q4ist4jH6uU · 108 Home Alone 2 k0kJieJ1k6k · 148 European
  Vacation A3OzNWTU2h4 · 155 Pulp Fiction s7kH1WYp_j8 · 184 Star Wars
  vZ734NWnAHA · 186 AotC gYbW1F_c9eM · 187 RotS 5UnjrG_N8hU · 185 TPM
  J3kyYFHdRsM · 191 T2 CRRlbK5w8AE · 1 Empire e0QkbuRaEDc · 206 Land Before
  Time 4BInhb4GkG8 · 221 Patriot OpKR4qTOVgI · 223 El Dorado JcOfJwN0bdY (no
  Apple — stays) · 224 Running Man b6rbNlkWscI · 228 School of Rock
  KdzWQT0wLCY · 229 Terminator nGrW-OR2uDk.
- **HDR trailers (clients):** Settings → Display → "HDR trailers" Auto/Always/
  Never (default Auto, per device; `hdr_prefs.dart`). Windows Auto = registry
  `MonitorDataStore\*\HDREnabled` (ELKO: 1 on DON + GSM entries). HDR →
  Big Picture fullscreen trailer plays via native mpv (`buildPlayerView`);
  hero stays SDR. Roku 0.1.8 auto-detects via GetDisplayProperties and adds
  `&variant=hdr` (hero too). Roku zip in ~/Downloads/NASCinema-roku.zip.
- **NAS was memory-starved** (30/32 GB, no swap; Sonarr 90% CPU, remuxworker)
  → a backend restart took ~3 min (import of FastAPI crawled). Not a code bug.
- **docs/SPEC-track-manager.md** (from the chat Claude) now in the repo —
  queued after Apple trailers + Big Picture.
- Next: Big Picture search (Y → on-screen keyboard), then Track Manager.

## Earlier (2026-09-25, night) — flag button (0.5.9+25), library rescan on hold

- **Flag button:** View (controller) / F8 anywhere → `POST /api/flags` with
  top screen, movie, trailer/movie + position, app version, context,
  screenshot (`<data_dir>/flags/<id>.png`). **Read open flags at the start of
  every session:** `curl -s http://127.0.0.1:8400/api/flags` on NASHOST;
  resolve with `PATCH /api/flags/<id> {"resolved":true,"resolution_note":…}`.
  Screens register via `FlagService.register(owner, screen, baseUrl, info)`
  (bp-home, bp-movie, bp-trailer, player, library, movie-detail). View is
  no longer Back (B is). Mid-movie screenshots lack the mpv picture.
  Flag #1 = smoke test (resolved).
- **Library rescan ON HOLD:** another Claude is replacing movies and stripping
  foreign audio/subs right now. 38 movies currently have no playable file
  (mid-replacement), 142 stale media_files rows (42 features, 100 extras).
  When Matt says it's done: `POST /api/scan` (long — run detached),
  `POST /api/reprobe`, show Matt the stale-row list before pruning, then
  retry the 40 movies without trailers (their `.none.json` markers are stale).
- 6 files have zeroed headers (unfinished torrents, Jun 29): HP 3/6/7/8 Open
  Matte x265 copies + Blue Collar One for the Road / Rides Again — told Matt.
- `POST /api/reprobe` ran once: first-ever media_streams for 261 files.
- **Trailer quality:** 1080p YouTube ≈ 3 Mbps median (86 trailers), 4K ≈ 10
  Mbps (65). Ideas: allow the m3u8 H.264 1080p (~4.3 vs 2.6 Mbps; needs the
  MKV-merge fix), Apple TV trailers (4K DV, not tried), previews cut from
  Matt's own files (best). Asked Matt whether 4K trailers also look soft (if
  so, suspect the player path).

## Session (2026-09-25, late) — trailer decode, quality labels, trailer identity

**Shipped:**
- **0.5.6+22 — trailers decode in software** (`hero_trailer_native.dart`,
  `hwdec: 'no'`). Matt saw a dotted "golf ball" patch mid-frame every few
  frames on ELKO (RTX 3070); the cached files decode clean on the NAS, so
  hardware VP9 decode is the suspect. **Awaiting Matt's check** — if it
  persists, look at the texture handoff next.
- **0.5.7+23 + Roku 0.1.7 — quality labels judged by 16:9-equivalent lines**
  (`max(h, w*9/16)`), not raw height. Cropped scope files (1920x816) showed
  "720p"; 102/210 files were mislabeled. Same `_lines()` fix in the trailer
  quality bar (it was rejecting cropped widescreen trailers). Test:
  `frontend/test/quality_badge_test.dart`.
- **Manual trailer pick always wins** (`1d03173`) — T2's 4K re-release
  trailer was beating the pinned original.
- **Library quality/YIFY report** for the other Claude:
  `D:\Temp\library_quality.json` on ALPINE (near-full rebuild territory).

**Trailer hunt (manual pins, frames checked by eye + audio language checked):**
- The Running Man (id 224) → `b6rbNlkWscI` (4K Cinema Trailer, English). The
  old one was German audio — frame checks can't catch audio; always check
  the audio language on search finds.
- European Vacation (id 148) → `A3OzNWTU2h4` (Trailer World, clean digital).
  The old one was a dusty 35mm print scan with rounded corners.
- `_fetch` now records `"pinned": true` / `"official": false` in
  `<id>.source.json` for manual picks (it wrote `official: true` for
  everything). **Code change needs a backend restart to take effect** — not
  done; rides along with the next deploy. The two files above were corrected
  by hand.

**Apple TV trailers — researched Sept 25 (not built yet):**
- Pipeline that works: TMDB id → Wikidata SPARQL (P4947 → P9586 "Apple TV
  movie ID", batch all ids in ONE query; WDQS was rate-limiting 1 req/min) →
  `https://tv.apple.com/api/uts/v3/movies/<umc>?caller=web&sf=143441&v=90&pfm=web&locale=en-US&utscf=…&utsk=…`
  (utsk/utscf scraped from any tv.apple.com page) → `playables.*.itunesMediaApiData.movieClips[].hlsUrl`
  → yt-dlp on the m3u8 directly (yt-dlp refuses tv.apple.com URLs as "DRM";
  trailer HLS has NO keys). Pick audio by `ba[format_id*=ac3]` (acodec shows
  "unknown"). Use `aec=UHD`. Prefer the SDR variant for the hero (HDR PQ
  variants exist; the texture path is SDR).
- Apple web search / iTunes Search API do NOT work for store movies (web search
  = Apple TV+ only; iTunes search returns 0 movies). iTunes lookup-by-id works.
- Survey of 219 library titles (script was /tmp/apple_survey.py on NASHOST):
  203 have an Apple trailer. vs current YouTube: 64 same-tier 1080p where Apple
  is ~2.5–3x bitrate (7–11 Mbps vs 2–4) usually with 5.1 AC-3; 15 Apple 4K
  (many HDR, 12–25 Mbps); 35 toss-ups (Apple 1080p vs YouTube 4K); 41 Apple
  worse (SD 480p ~2 Mbps — keep YouTube); 28 movies with no trailer today get
  an HD/4K Apple one. Waiting on Matt re: whether YouTube 4K looks soft.

**Later, Sept 25 — dubbed trailer audio (0.5.8+24):**
- **Root cause of German trailers:** YouTube auto-dubs trailers (8+ audio
  tracks); `-S res,br` outranked yt-dlp's default `lang` sort, so the audio
  track was picked by bitrate and dubs edge out the original by ~0.004 kbps
  (Empire picked pt-BR). Now `-S lang,res,br`. Deployed (full deploy).
- The 16 trailers with dub tracks were re-downloaded (same video key). Empire,
  Inglourious Basterds and Star Wars came back 1080p (YouTube stopped
  offering 4K), so their old 4K video was remuxed with the new original
  audio. Backups (`.mkv.bak`, `.mkv.1080`) deleted on Matt's say-so.
- **Whisper audit of all 166 cached trailers** (faster-whisper small, CPU,
  venv `D:\Temp\whisper-venv` on ALPINE; `D:\Temp\langcheck.py`,
  results `D:\Temp\langcheck.tsv`): everything English except
  **Beverly Hills Cop III** (German — the cached file was `hakuZ8xvJ4Q`
  "Kino Trailer Deutsch" though source.json said `XH3VbQMv-Nk`). Pinned
  `BhfZMtv9XuE` (1080p, English by Whisper, frames clean). Low-confidence =
  no dialogue (Freddie Mercury concert, JW Rebirth teaser, Die Hard 5 promo).
- **Recipe for future hand-picks:** frames AND Whisper on the audio
  (`D:\Temp\langcheck_dir.py <folder>`).
- **0.5.8:** `CursorAutoHide` (frontend/lib/widgets) — any pad press, right
  stick or key hides the cursor app-wide via a translucent top MouseRegion
  (beats buttons' own click cursor); mouse movement shows it. Test:
  `cursor_auto_hide_test.dart`.
- NAS scratch + stale `*.part` downloads deleted (1.9 GB). Still on ALPINE:
  `D:\Temp\langclips*`, `D:\Temp\whisper-venv` (reusable for audits).

**Still open:** 13 movies on search-picked trailers (all passed the Whisper English check) (Land Before Time, Big
Daddy, Big Fat Liar, Coming to America, Home Alone 2, Lethal Weapon 2 & 3,
Miracle on 34th St, Christmas Vacation, Osmosis Jones, Space Jam, Santa
Clause 2, Waterboy) — worth an audio-language re-check; Bruce Almighty +
Django are backdrop-only; 20 stale `.none.json` markers; 6 unprobed files
(DH1, DH2, HBP, PoA, two Blue Collar specials). Nothing pushed to GitHub.

## Session (2026-09-24) — NAS backend committed, public domain restored, release pipeline fixed

**Direction (Matt, Sept 24 — supersedes the Sept 13 "Roku primary, lossy OK"):**
Matt is switching back from Jellyfin to NASCinema for real (JF desktop has HDR
fullscreen issues + no controller support; Sonarr dropped). He loves the Roku
client but NOT its lossy audio. **ELKO is a main client again.** Complaint: the
ELKO app feels like the YTS website while the Roku feels like Netflix. Decision:
keep the mouse UI AND add a **"big picture mode"** (fullscreen, controller +
keyboard focus nav, Roku as the design source of truth, Netflix-style detail
page with a "Versions & audio" picker tucked behind a button). **No Shield — never
ordered.** TV shows (Jellyfin parity) will be needed eventually; not started.

**Done this session:**
- **Committed the Sept 13–14 work** (`e60ee2c`), byte-identical to what's
  running on the NAS: backend Dockerfile/entrypoint, `deploy/nas/` (compose,
  deploy.sh, .env.example), migration 0010 `media_streams` + `media_files.edition`,
  `POST /api/reprobe`.
- **NAS backend state** (`/mnt/NAS Storage/apps/nascinema/`): containers
  `nascinema` (:8400, host net) + `nascinema-postgres` (:5435) healthy; DB at
  migration 0010, 409 media_files, **0 media_streams rows — reprobe never run.**
  Health still reports version "0.3.7" (backend version string never bumped).
- **`nascinema.simpson1045.com` was DEAD since the TrueNAS move (~July):** no NPM
  proxy host existed for it (NPM #7 was an old mcp.* host, not NASCinema). The
  Roku (`MainScene.brs` m.base), ELKO's saved server, and the cast HTTPS base
  all use that hostname. **Matt added NPM proxy host Sept 24** → 192.168.0.248:8400,
  LE cert (to Dec 23), websockets on, block-exploits off, advanced:
  read/send timeout 3600, proxy_buffering off, client_max_body_size 0.
  Verified: public health 200, update/check 200 from ELKO, Range → 206.
- **Release pipeline to the NAS:** `deploy.sh --updates` (installed on the NAS,
  backup `deploy.sh.bak-20260924-preupdates`) pulls `backend/updates` +
  `CHANGELOG.md` from ALPINE, `version.json` LAST, no restart. Full deploy uses
  the same ordering. `CHANGELOG.md` was never deployed before → the updater
  showed empty release notes; fixed. **Release = `backend\release.bat X.Y.Z N` on
  ALPINE (run as an ADMS start_job on NAS that SSHes to ALPINE — Gradle outlives
  the 300 s run_command cap), replace the CHANGELOG TODO stub, then
  `sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" --updates` on NASHOST.**
- ELKO was running **0.4.0+13 (Jul 1)** = the newest release on the server, so
  the Aug 23 work (hero trailers, theater hooks, TrueHD→LPCM) never reached it.
  **0.4.1+14 built + published Sept 24** (zip md5 abf6c6ab… verified on the NAS,
  served at the public URL with release notes). ELKO updates when Matt opens the
  app and accepts the prompt — first real test of the Windows self-update path.

- **ELKO updated 0.4.0 → 0.4.1 in-app (Sept 24) ✅** but the old .bat helper
  hung: a detached cmd has no console, so `tasklist|find` each got their own
  console window and `find` blocked on that window's keyboard until Matt hit
  Ctrl+C. **0.4.2 replaces it with a hidden PowerShell helper** (Wait-Process on
  the app PID → hidden robocopy → relaunch → deletes extract dir, zip, itself);
  dry-run tested on ELKO. 0.4.2 itself still installs via 0.4.1's old helper
  (one last Ctrl+C); silent from then on.
- ELKO had **no shortcut** to NASCinema (only `C:\NASCinema\renderer\nascinema.exe`);
  added Desktop (OneDrive) + Start Menu shortcuts Sept 24.
- Roku channel repackaged (`roku/roku-channel.zip`, no Thumbs.db) and copied to
  ELKO `Downloads\NASCinema-roku.zip`; Matt sideloads via http://192.168.0.78
  (rokudev — password is Matt's, Claude doesn't enter it). Roku has developer
  mode on.

- **Roku home redesign (channel build 0.1.2) — Matt: "MUCH better" ✅.** Hero is
  full-bleed 1920x1080 behind everything (`home_scrim1.png` fades it into the
  rails + darkens the left); logo/meta/overview/dots upper-left on home, lower-left
  when the hero is focused (fullscreen). Trailer scaled 1.15x (2208x1242 @
  [-144,-159]) so 2.39:1 baked-in letterbox bars fall off-screen. RowList shows 2
  rows from y=540 so the next rail peeks; Continue Watching (any rail whose items
  carry `resume_position`) renders 480x270 backdrop cards + amber progress bar
  (resume_position s / runtime min), other rails 200x300 posters. **This is the
  design source of truth for big picture mode** — and the ELKO hero's
  centered info column is wrong: info goes left, like here.
  Roku dev password was reset Sept 24. **Roku zips go to the Mac's
  `~/Downloads/NASCinema-roku.zip`** (not ELKO — input switching).
- **Trailer letterbox handling (Roku 0.1.6, Matt: fullscreen "looks right") ✅.**
  Zooming trailers was REJECTED (chops titles/text) — never zoom or crop. Server
  measures each trailer's bars once (ffmpeg cropdetect → `<id>.bars.json`,
  `trailer_bars {top,bottom}` as fractions of a 16:9 screen, in `/api/home`
  featured items; short clips sampled from 15%, implausible readings = 0). Home:
  trailer slides up by its top bar, bottom lands under the rails. Fullscreen:
  centered, bars top and bottom. Black rect behind every playing trailer;
  backdrop hidden while it plays. Rails use RowList `fixedFocus` (focused rail
  stays in the top slot; floatingFocus left it half off-screen). Overview 760px
  wide over a darker left gradient (`home_scrim2.png`). Unexplained once: a
  Goblet of Fire trailer shown shrunk with side bars during the 0.1.4 slide — not
  seen since the fullscreen slide was removed.

- **Big picture mode step 1 — 0.5.0+16 published Sept 24 (NOT yet seen on ELKO).**
  `lib/screens/big_picture/` (`big_picture_screen.dart` + `bp_hero.dart`): fixed
  1920x1080 canvas in a FittedBox, Roku-parity layout (hero full-bleed, info
  upper-left, rails from y=540 with fixed-focus scrolling, wide Continue
  Watching cards, trailer slide/center via `Movie.trailerBars`, trailer view
  `BoxFit.contain` — never crops). One nav model in `_onKey` (arrows / Enter /
  Esc) that the controller will feed next. Boot: `ConnectScreen` → BigPicture
  when `startInBigPicture()` (pref `big_picture_start`, default ON, desktop
  only; Settings → Display toggle). Back on home → menu (Exit / Settings /
  Quit). Pushed pages (detail/settings) get Esc→pop via CallbackShortcuts.
  Mouse layout fix: hero info was centered by AnimatedSwitcher's default
  layout → now bottomLeft. `flutter analyze` runs clean from a local rsync copy
  on the Mac (`~/development/flutter`). NEXT: step 2 XInput controller, step 3
  big-picture movie page, step 4 Versions & audio (+ reprobe), step 5 player.

- **Trailer quality overhaul (Sept 24) ✅ (backend only, verified by numbers).**
  Picker now probes every candidate (manual + TMDB Trailer/Teaser + YouTube
  search "<title> <year> official trailer 4K") with `yt-dlp -J` and downloads
  the sharpest (res, then bitrate; no AV1, no HLS/m3u8 — TS won't merge to
  MKV). Bar: >=1080p, 2.8 kbps/line H.264 (0.7x VP9); nothing good -> backdrop,
  `<id>.none.json` for 7 days. Search guard is word-based (sequel numbers,
  other years, reactions/clips/AI upscales rejected). Re-pull: 12 trailers
  1-2.7 Mbps -> 4K 6-15 Mbps; Terminator 1.1 -> 2.8 H.264 (manual pick);
  Crystal Skull 3.9. **Chamber of Secrets (#100) still 1.3 Mbps** — its manual
  YouTube pick is gone and nothing on YouTube clears the bar. #125 is an orphan
  trailer (no movie row). Leftovers in data/trailers NOT deleted (need Matt's
  yes): `*.prequality.mkv` / `*.prequality2.mkv` backups, and unmerged
  `100.f270.mp4`, `100.f140-drc.m4a`, `112.f270.mp4`, `112.f140.m4a`,
  `112.temp.mkv`.

- **Library repair (Sept 25) ✅.** Scanner: extras folders matched by pattern at
  any depth (`_is_extras_dir`: "bonus", "special feature", "production photo"…),
  movie = folder above the OUTERMOST one; a top-level "… Bonus Disc" belongs to
  the film it names. No-year folders keep their full name (guessit had cut
  "Jurassic World - Dominion" to "Jurassic World"). TMDB `_pick`: exact title,
  then year, then TMDB order (was results[0] -> JW/FK/Dominion all filed under
  Rebirth, DH Part 2 under Part 1, Lost World -> a 1960 film). Repaired IN
  PLACE (files re-pointed, no file rows deleted, watch progress kept): 126
  files moved, 118 fake movies removed; library = 206 movies, 0 extras-only.
  Backup: `/mnt/NAS Storage/apps/nascinema/nascinema-20260925-prerepair.dump`.
- **Big picture web preview ✅:** `http://192.168.0.248:8400/?bp=1` (auto-
  connects; no trailers on web). `&keys=down,down,right,up,back,enter` replays
  presses after load, so Claude checks layout from screenshots — the browser
  pane PROMPTS on every click/typed key (no always-allow), so never type into
  it. Web builds on the Mac (`flutter build web --pwa-strategy=none` in a local
  rsync copy) -> copy to ALPINE `frontend/build/web` -> `deploy.sh --web` (no
  restart). Verified: home layout, rail scrolling, hero fullscreen. **OPEN: Back
  on home closes big picture in the browser instead of opening the menu** —
  suspected web-only (dialog vs browser history), unproven.

- **PAUSED Sept 25 ~12:08 — NAS shut down so Matt can install an SSD.** On resume:
  (1) restart the trailer backfill: `/tmp/alltrailers.py` lived in the container
  and is GONE after reboot — rewrite it (loop all movies by popularity; skip
  `is_cached` / `_recently_found_nothing`; `ensure_trailer(id, tmdb, override,
  title, year)`), run via ADMS start_job -> ssh admin@192.168.0.248 `sudo docker
  exec ... nice -n 15 python -u`. ~175 movies needed one; any `.part` leftovers
  are harmless. Then make the home hero pick featured movies from ALL movies
  with a cached trailer (currently random 8 of the top-30 popular).
  (2) Back-menu bug: temporary `[bp-debug]` debugPrints are in
  `big_picture_screen.dart` (uncommitted) and in the published web build; the
  console showed NO bp-debug lines on `?bp=1&keys=back` — next step: confirm the
  replay even runs on that URL (maybe the page reloads/loses BP before the key).
  Remove the debug prints before committing.
  (3) then step 2: Xbox controller. Later: series/franchise pages (TMDB
  collection_id is stored; Marvel/DC/Star Wars need companies/keywords + manual).

- **UPDATER (final, 0.5.4): NASRadio's updater lifted verbatim** — `cmd /c start
  "NASCinema Update" cmd /c <bat>` (start gives the bat a REAL console; robocopy
  /R:30 /W:1; log %TEMP%\nascinema-update.log). 0.5.2's conhost --headless ALSO
  failed from the GUI app (it only worked from a console parent in my test), and
  an in-process rename-swap was built then dropped for the proven code. ELKO
  hand-installed to 0.5.4 (backups renderer.bak-0.4.2 / .bak-0.5.2). The NEXT
  release is the first real in-app update test. LESSON: check NASRadio/KYLIE
  before writing app infrastructure.
- (history) **UPDATER WAS BROKEN 0.4.2 -> 0.5.1; 0.5.2's fix didn't hold.** Dart's
  detached Process.start gives the child NO console and powershell.exe exits
  instantly — the helper never ran, the app just closed ("crashed") on every
  update, so ELKO sat on 0.4.2 and never got big picture. Verified on ELKO via
  CreateProcessW with Dart's flags (didn't run) vs `conhost.exe --headless
  powershell ...` (ran). update_service now launches through conhost
  --headless. ELKO bootstrapped to 0.5.2 by hand over ADMS (backup
  `C:\NASCinema\renderer.bak-0.4.2`); future updates should self-install —
  first real proof will be the next release. The WER "crash" at 13:51 Sept 25
  was the queued 0.4.1 report from Sept 24, not a new one.
- Controller (0.5.1): `lib/services/gamepad/` XInput FFI + PadDispatch; Back
  menu verified by widget test (web-preview Back quirk is browser-only).
- Trailer backfill for all movies running (`/tmp/alltrailers.py` in the
  container); after it finishes: home hero picks featured from ALL movies with
  a cached trailer (needs a backend deploy = restart, so wait).

- **Trailer identity audit (Sept 25) ✅.** YouTube-search picks put WRONG
  content in the hero (Sorcerer's Stone = the HBO Max series teaser; Jurassic
  World = Dominion; Ride Along = a lowrider car show; fan frames, burned-in
  subs, SBS 3D, someone filming their TV). Auto picks are now OFFICIAL ONLY
  (manual + TMDB list; best that clears the bar, else best official 1080p+,
  else backdrop); `search_offers()` is for a human-verified hunt — pull frames
  and LOOK before pinning. Every trailer has `<id>.source.json`. Audit: 67
  matched an official trailer by length, 85 suspects frame-reviewed by Claude
  (68 fine, 17 bad -> replaced with official; Bruce Almighty + Django have no
  watchable official = backdrop). Sorcerer's Stone: title renamed to US, US
  poster (/lz1qjw1wDbE2Kj76iTXpGKQSPKD.jpg), genuine trailer q4ist4jH6uU;
  Chamber pinned to oQtgBqXMgv0 (both are SD originals upscaled — no real HD
  exists; idea: build previews from the movie's own 4K file). Frame-check
  recipe: yt-dlp -g + ffmpeg -ss 30/60/90 -> hstack strips -> transfer to
  ALPINE D:\Temp -> Read the jpgs. 20 movies carry old .none.json markers
  (expire in 7 days). 0.5.5 published (one persistent hero trailer player =
  crash fix; hero follows highlighted movie); not yet installed on ELKO —
  it's the first real test of the NASRadio updater.

**Known broken / not verified:**
- **C2 PC-label guard in `webos_control.dart` will likely fail:** direct
  `ssap com.webos.service.eim/setDeviceInfo` returns **401** with our pairing key
  (memory, Sept 23). What works: `system.notifications/createAlert` with a button
  whose onClick = `luna://com.webos.service.eim/setDeviceInfo` — Matt presses OK
  on the TV. Rework the guard to that.
- Refresh-rate switching can turn Windows HDR off (Win+Alt+B) — the open
  question from the Aug 23 notes is answered: yes, it can. Needs a re-assert.
- Theater hooks (Denon/TV/refresh) still untested on hardware; all default OFF.
- Denon 8K input is now labeled "ELKO" (SI8K). C2: HDMI_2 = Denon, HDMI_4 = ELKO.

**Next (agreed order):** finish 0.4.1+14 → ELKO updates in-app → **big picture
mode**: write a short plan first (entry/exit, focus/controller nav, Roku look,
detail page), Matt approves, then build screen by screen starting with home.
Parked: reprobe, C2 guard fix, hook hardware tests, backend version string.

---

## Session (2026-08-23) — un-abandoned; ELKO-only theater; theater hooks built

**Context (full saga in the ADMS memory CLAUDE.md, every "2026-08-23" section):**
the project was abandoned on a false premise (that Jellyfin could do lossless via
Cast/Roku — nothing can; TrueHD/DTS-HD bitstream is licensing/silicon-gated to
HDMI-input boxes). Last night proved the whole chain live: **ELKO → Denon 8K input,
DTS:X MSTR and TrueHD both locked**, HDR + 23.976 + C2 film mode. Product
definition now: **ELKO (this Windows app) = the theater; Cast/Roku = lossy
convenience; phone = remote. No Shield, no Android TV client** (decision made then
reversed same night — "I'm greedy": ELKO does 4K120 5:5 cadence + SVP option).

**Done this session (committed on main, pushed — origin is current):**
- Reconciled the long-uncommitted tree: mpv async-SetWindowPos deadlock fix +
  leash diagnostics + Roku HttpTask POST + filled the 0.4.0 CHANGELOG stub.
  Pushed the whole 60-commit backlog to GitHub.
- **Theater hooks** (`frontend/lib/services/theater/`, all config-driven via
  Settings, all off by default, all best-effort):
  - `denon_control.dart` — telnet ZMON + SI\<input\> on Play (X3700H = .67, input 8K).
  - `webos_control.dart` — LG SSAP client (wss:3001, pairing key persisted).
    **C2 PC-label guard**: if the configured input's label flipped to "PC" (SPD
    auto-relabel → kills TruMotion/Real Cinema, the "no butter" bug), rewrite it
    via `com.webos.service.eim/setDeviceInfo`. Optional TV input switch.
  - `refresh_rate.dart` — ChangeDisplaySettingsEx match to mpv's container-fps on
    play, restore on stop; leaves integer multiples (4K120) alone; after a switch
    the exclusive audio endpoint is re-checked (`ensureAudioAlive`).
  - `settings_screen.dart` — new gear icon on the library bar; Denon/TV/display/
    renderer sections + TV pairing flow (TV shows an accept prompt once).
- **TrueHD bitstream now OFF by default** (decodes to lossless multichannel LPCM):
  ffmpeg's spdif MAT packer dies at seamless-branch splices (ROTS @2:20) and the
  upstream fix is regressed on real AVRs — our report: mpv-player/mpv#13943.
  Settings → Renderer toggle re-enables when a fixed build lands. DTS-HD/EAC3/AC3
  still bitstream.
- **Backend WOL**: `POST /api/renderer/wake` sends a magic packet to
  `NASCINEMA_RENDERER_MAC` (get ELKO's via `getmac`; not yet in .env). The
  phone-side "wake ELKO then play on it" flow needs the Phase-3 remote channel.
- **FeaturedHero ported from Roku to the Flutter home** (`home_widgets.dart` +
  `hero_trailer*.dart`): shuffled order, backdrop beat → cached-trailer autoplay
  (media_kit texture, dissolves in only after the first real frame renders),
  25s idle cap, hover(1.2s)-to-fullscreen with unmute, fade-through-black on every
  advance/mode change, suspend while a route covers home. Web home stays
  backdrop-only (conditional import keeps media_kit out of the web bundle).

**NOT yet verified on hardware (needs an ELKO deploy — ask Matt first):**
everything above. Specifically test: Denon telnet fires on Play; C2 guard
(unplug/replug or reboot ELKO to trigger the PC relabel); refresh match at 60 Hz
desktop (**and whether Windows HDR survives the mode change** — open question from
the RefreshSync notes; if it drops, re-assert via DisplayConfigSetDeviceInfo);
TrueHD-decode default plays ROTS past 2:20 with the Denon showing multichannel PCM;
hero trailers actually render on ELKO's ANGLE (first-frame gate means failure =
backdrop-only, not black).

**Deliberately NOT done (needs Matt's nod / hardware):** mpv conf parity items from
the shim testing (`video-sync=display-resample`, `gpu-api=d3d11`, explicit
`hwdec=d3d11va`, `audio-delay=0.100`) — the app's current flag set is the verified
M2/M3 state and display-resample against an un-stretchable bitstream clock caused
the pause/speed-up artifact when rates mismatched. Revisit deliberately, one flag
at a time, on hardware. Also future: ELKO sleep + phone "Play on ELKO" (Phase-3
remote channel), XInput controller, "Who is that?" X-Ray overlay (memory
2026-08-23 18:10), Motion toggle (SVP/RIFE — memory 18:21).

---

## Latest session (2026-07-01) — TrueHD passthrough "blip on loud peaks" SOLVED ✅

- **THE FIX: `--wasapi-exclusive-buffer=100000`.** mpv's WASAPI **exclusive** buffer
  defaults to the device's tiny **10 ms** period; a loud transient blows that deadline →
  an audible blip. Setting it to **100 ms** gives mpv the slack VLC already uses →
  **zero blips** confirmed by ear through the loud 13:00–17:00 ROTS stretch on ELKO.
- **Sub-track switch re-buffer (old item 2) also GONE** — reading direct off the NAS
  with the 1 GiB demuxer cache, toggling subs no longer pauses playback. Both HANDOFF
  tuning items are now closed.
- **Ruled out first (don't re-chase):** backend HTTP (mpv reading the NAS file DIRECT
  still blipped), network cache (blip mid-playback, buffer full), WASAPI buffer
  *starvation* (padding never dropped — the `ao` trace only shows the topped-up state),
  seeks (blip after a full steady minute), and the codec (EAC3 JOC Atmos blipped too →
  NOT TrueHD-specific). **Two dead ends:** the mitzsch TrueHD-patched build (2026-06-27)
  made it WORSE (abandoned); and my early "backend is exonerated" claim was wrong — it
  rested on a VLC-through-backend bat Matt never ran (his flawless VLC test was
  **direct off the NAS**).
- **Direct-NAS is the renderer's byte path.** ELKO plays from
  `\\192.168.0.248\Totally Legal Movies_2\...` directly (VLC's flawless path). Note the
  **`_2`** share, and that **only Matt's interactive login has NAS creds** — the MCP
  connector's service session can't see the share (its `Test-Path` fails; a bat Matt
  double-clicks works). The native renderer should **direct-play off the NAS**, not via
  backend HTTP (the backend stream is the phone/remote fallback path).
- **Reference invocation (test bat: `Desktop\Play ROTS (mpv BUF).bat` on ELKO):**
  `--fullscreen --hwdec=auto --aid=1 --audio-spdif=truehd,dts-hd,eac3,ac3
   --audio-exclusive=yes --wasapi-exclusive-buffer=100000 --audio-buffer=1.0
   --cache=yes --demuxer-max-bytes=1GiB --demuxer-max-back-bytes=512MiB
   --demuxer-readahead-secs=60`
- **SINGLE-WINDOW EMBED + IPC CONTROL PROVEN ✅ (same session).** Matt wants the player
  contained in the app window (no separate mpv window) — proven possible with full
  quality via a **`--wid` native child-window embed** (mpv keeps its own d3d11/gpu-next
  pipeline → 4K HDR DV + lossless Atmos intact; this is NOT the broken ANGLE-texture
  path that killed media_kit). Harness: `Desktop\embed_test.ps1` + `Play ROTS (mpv
  EMBED test).bat` on ELKO (WinForms host, panel handle → `--wid`). All verified live:
  embedded DV render, correct fill, IPC pause/seek/sub-toggle, **amber `#FFB020` OSD
  theming**, hover-summoned auto-hiding controls w/ cursor hide, clickable/draggable OSC.
- **Embed gotchas (each cost a debug round — bake into the Flutter integration):**
  (1) host must be **DPI-aware** (`SetProcessDpiAwarenessContext(-4)`, per-monitor v2)
  or the video renders zoomed/cutoff on the 4K C2; (2) in `--wid` mode the **host owns
  all input** — forward mouse/keys to mpv over IPC (`mouse x y`, `keydown MBTN_LEFT`,
  `keypress`); (3) the IPC pipe MUST be opened **async/overlapped**
  (`PipeOptions.Asynchronous`) — a sync handle serializes reads+writes and the bridge
  goes mute after one command; (4) **drain mpv's replies** on a reader thread and queue
  writes off the UI thread or the pipe deadlocks (froze the UI once); (5) throttle
  mouse-move forwarding (~30/s); (6) drive OSC visibility from the host
  (`script-message osc-visibility always/never no-osd`) — deterministic show-on-move /
  hide-on-idle instead of trusting synthetic-event hover detection.
- **M1 SHIPPED & VERIFIED ON ELKO ✅ — Play → native mpv works from the app.**
  New `frontend/lib/services/mpv/`: `named_pipe.dart` (hand-rolled kernel32 FFI,
  overlapped handle, reader/writer isolates — the six gotchas encoded),
  `mpv_ipc.dart` (JSON IPC, request_id correlation, observe_property),
  `mpv_controller.dart` (process launch + mirrored state + control API; mpv path
  configurable via `mpv_path` pref). `player_view_native.dart` seam now branches:
  **Windows → mpv, Android keeps media_kit** (phone unregressed). Backend
  `/api/play` returns `path` (UNC) for `client=native` + direct mode → the app
  plays straight off the NAS. Resume via `--start`. M1 = mpv's own fullscreen
  window (native keys + stock OSC); M2 = the `--wid` embed.
  **Verified live by Matt: movie + lossless audio play from the app's Play button.**
  (App control bar over IPC while mpv runs: wired, not yet explicitly verified.)
- **Gotcha #7 (cost a frozen-black-window round): a child process's PIPED
  stdout/stderr MUST be drained** — mpv wrote its terminal status into
  Process.start's pipes, filled them, and its core blocked mid-load. Fix:
  `--terminal=no` (+ mpv's own `--log-file` next to the exe) and drain both
  streams anyway. Confirmed by mpv's IPC accepting connects but never answering.
- **QoL batch shipped same day (all verified):** 🔍 **Search** (`search_screen.dart`,
  icon in the library bar — type-ahead over `/api/movies`, prefix-ranked);
  🚪 **auto-connect** (saved server → splash → library; form only on first run /
  failure / back-out); 🪟 **window size/position/maximized persistence**
  (`fullscreen_io.dart`). Deployed to ELKO via robocopy (NOT a versioned release
  yet — still 0.3.13+12 internally; next release should bump, it's earned).
- **ELKO SMB note:** deploys can hit "no more connections" (client-SKU ~20-session
  cap) — fix is `Get-SmbSession | Close-SmbSession -Force` **on ELKO**, then retry.
- **M2 + M3 SHIPPED THE SAME DAY (marathon session, all verified on ELKO):**
  single-window embed works; movie full-bleed; **uosc** (amber-themed, in
  `<exe>\mpv-config`, staged into the Release dir on ALPINE — `flutter clean`
  wipes it, restage from this session's recipe or commit it) is the on-video
  control surface with back/fullscreen buttons wired to the app via
  `client-message`/property intercepts; pointer events fall through the native
  windows into Flutter and are forwarded to mpv over IPC (throttled); hotkeys
  Esc/Backspace=exit C=subs I=stats P=audio F=fullscreen; modal sheets hide the
  video while open; stats button = mpv's own stats page; **HDR passthrough**
  (`--target-colorspace-hint=yes` + Windows "Use HDR" ON — was tone-mapping to
  203-nit SDR before, "vibrant now"); **DPI fix** = `SetProcessDpiAwarenessContext`
  forced in `runner/main.cpp` (manifest present but ignored → app ran
  DPI-virtualized, 4K rendered at 2560-wide); window state persists incl.
  fullscreen (restore must run in `waitUntilReadyToShow`, and fullscreen saves
  immediately — debounced saves lost F11-then-quit).
- **Hard-won pipe/process gotchas (in code comments + memory too):**
  GetLastError is CLOBBERED by the Dart runtime between FFI calls — never branch
  on it; pre-set OVERLAPPED.Internal=STATUS_PENDING and let
  GetOverlappedResult(bWait) decide. `Uint8List` IS a `List` — type-check data
  FIRST when multiplexing isolate messages (replies were routed into the error
  path and discarded: live scrubber died). Widget-identity: hiding chrome by
  removing children rebuilt the video subtree → **respawned mpv per toggle**
  (multi-instance incident; audio kept playing after app close). Fixes: stable
  children shape + GlobalKey (Matt's), serialized launches, and a **Windows Job
  Object (kill-on-close) leash** (`job_leash.dart`) so mpv can never outlive the
  app. Child stdout/stderr must be drained (`--terminal=no` + listeners).
  Audio-alive check = `current-ao` (NOT `audio-params` — decoder-side, false
  positive). **Audio fallback ladder**: exclusive 100ms → 50ms → default → PCM;
  JP's DTS-HD hits AUDCLNT_E_ENDPOINT_CREATE_FAILED at every exclusive buffer on
  the NVIDIA endpoint (TrueHD is fine) → lands on lossless PCM decode (Windows
  spatial wraps it as Atmos on the Denon). DTS-HD bitstream = open quest
  (check "allow exclusive control" on the endpoint).
- **Library repair COMPLETE:** 48/48 zero-filled corpses restored from D: (297GB,
  filename+size-fingerprint matching; JP renamed clean, plays, probed). Probe bug
  fixed: `subprocess.run(text=True)` decoded ffprobe output as cp1252 → died on
  UTF-8 tags; now `encoding="utf-8", errors="replace"` ([probe.py]). **6 true
  orphans need re-acquisition:** Blue Collar Comedy ×2, HP KONTRAST ×4.
- **OPEN:** uosc styling iteration (Matt: "meh" — conf-file tweaks, no rebuild);
  embedded subtitle tracks (JP's PGS) in the subs menu; grain = film grain +
  C2 HDR preset sharpness (TV-side); TruMotion needs input icon ≠ "PC";
  **0.4.0+13 release**: pubspec already bumped (killed release.bat run mid-way —
  CHANGELOG has an unfilled stub), re-run `release.bat 0.4.0 13` when stable,
  Android build UNTESTED with all this (media_kit leg preserved by design).

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
- **Backend streaming was the real culprit behind the stalls/glitches** (user
  nailed it: VLC reading the NAS file *directly* = flawless; through the backend =
  stalls). Cause: Starlette `FileResponse` reads **64 KiB** chunks → ~850k tiny
  SMB round-trips on a 52 GB REMUX → stalls under load. Replaced
  `/api/stream/{id}/direct` with a custom Range-aware `StreamingResponse` reading
  **4 MiB blocks** off the loop via `to_thread`. Measured **0 B/25s → 72–78 MB/s
  stable**. Committed. (Also: if the backend ever wedges on stale NAS reads after
  a NAS reboot, restart it — fresh SMB session fixes it.)
- **mpv playback state (ELKO, via desktop `Play ROTS (mpv test).bat`):** 4K HDR DV
  picture (gpu-next, looks great) + lossless TrueHD Atmos, smooth stream. **Two
  refinements left, both tuning not walls:** (1) **audio crackle on loud peaks** —
  WASAPI *exclusive* passthrough thread keeps resetting (device buffer only 1920
  samples); `--hwdec=d3d11va` made it worse, reverted to `--hwdec=auto`. Needs an
  `ao=v` log captured during a steady loud scene (no seeking). (2) **switching sub
  tracks re-buffers** the network stream (mpv re-reads for the new track).
- **Next session:** nail those two, then the real integration (Play → launch mpv
  with `--input-ipc-server` + control it for on-screen controls + phone remote).

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
