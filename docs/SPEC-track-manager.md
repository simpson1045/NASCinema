# NASCinema — Track Manager (Audio/Subtitle Stripping) — SPEC

**Status:** TODO (queued behind Apple trailers + Big Picture mode)
**Author:** Claude (chat), from a working session with Matt, Sept 25 2026
**Goal:** Let Matt inspect any movie's audio/subtitle tracks in NASCinema, pick what to keep, and strip the rest losslessly — manually per movie, in bulk across the library, and automatically when downloads finish.

---

## 1. Why

- RuTracker / international remuxes carry 5–15 foreign dubs (Russian MVO/DVO/AVO voiceovers, FR/DE/IT/ES AC3, etc.) + foreign subs. On DVD-era content that's ~30% of the file; on UHD remuxes it's 2–12 GB per movie.
- Worse: foreign dubs are often flagged **default**, so clients (Roku, TV apps) play Russian first.
- Proven manually Sept 23–25 2026: Tom & Jerry strip saved 18.4 GB, Sorcerer's Stone remux saved 10.1 GB, Groundhog Day 12 GB, JL/JLU ~9.3 GB. Library-wide scan found **259 movies with foreign tracks, ~92 GB** (≈70 GB excluding protected fan preservations).

## 2. Features

### 2.1 Per-movie Track Picker (UI)
- On a movie's detail page: table of every stream — type, index, language, codec, channels, bitrate/est. size, title tag, default/forced flags.
- Checkboxes with smart defaults pre-ticked (see §3 rules).
- Live **"space saved"** estimate (track bitrate × duration; fall back to stream `BPS` tag).
- "Protect this movie" toggle (never strip).
- Apply → enqueues a job (§4). Show job status/progress.
- Controller-friendly for Big Picture mode.

### 2.2 Library-wide bulk strip
- Scan all movies (ffprobe), list files that have removable tracks, **sorted by savings desc**.
- Filters: min savings, has-default-foreign-audio, source group, etc.
- Select-all / per-row approve → enqueue.
- Show separate section: "Protected — skipped" (so Matt can see they were intentionally excluded).

### 2.3 Auto-strip on download complete
- When a torrent completes: probe → apply rules → stage-strip → verify → place into library (and optionally replace an older copy of the same title, e.g. a YIFY).
- Configurable: auto / ask first / off.

## 3. Rules (hard-won — keep these exactly)

**Keep audio if:**
- `language` is `eng`/`en`, OR
- `language` is missing/`und` **AND** title does **not** match the dub regex below.
- Always keep commentary tracks (English). Keep alternate English mixes (e.g. "Original Mono", "Theatrical Stereo").

**Dub regex (drop even if untagged):**
```
[\u0400-\u04FF]|\b(dvo|mvo|avo|dub|dubbed|voice.?over|gavrilov|volodarsky|rus|ukr)\b   (case-insensitive)
```
> Real incident: Sorcerer's Stone remux had a Russian voiceover with **no language tag**, title `DVO, LDV / "Легендарный"`, as audio #1 → survived an "eng+und" rule and played by default.

**Subtitles:** same keep rule (eng/en, or und without dub markers).

**Ordering / flags:**
- Sort kept audio: English-tagged first, commentary last.
- Clear all audio default flags, set **first kept audio = default**. Clear subtitle default flags.

**PROTECTED — never touch (filename/path regex, case-insensitive):**
```
harmy|4k77|4k80|4k83|35mm|despecial|open.?matte|reel|print|scan|fan.?edit|preserv
```
These fan-preservation projects (Harmy Despecialized SW, 4K77/80/83 35mm scans, Jurassic Park 35mm theater reels/open matte) bundle **irreplaceable alternate English mixes** (e.g. ANH 1977 mono) often tagged with odd/non-English language codes. Language-based stripping would destroy them. Plus a per-movie manual protect flag.

**Skip if:** no English audio at all (log it), or already clean (nothing to drop → don't rewrite).

## 4. Engine (already exists — reuse it)

Working reference implementation on the NAS: **`/root/remuxjob/remux_worker.py`** (runs as systemd unit `remuxworker`).
- Queue file `/root/remuxjob/queue.txt` (paths relative to `/mnt/NAS Storage/movies`), done list `/root/remuxjob/done.txt`. Worker polls every 60 s, processes in order, marks done. Helper: `/root/remuxjob/remuxq add|status`.
- Per job:
  1. ffprobe (via the Jellyfin image's `/usr/lib/jellyfin-ffmpeg/ffprobe`, run with `docker run --rm` since TrueNAS host has no ffmpeg).
  2. `ffmpeg -c copy` mapping only kept streams, `-map_chapters 0 -map_metadata 0`, default-flag fix → write to **SSD staging** `/mnt/scratch/remux/movies/`.
  3. **Verify:** duration within 15 s of original AND kept-audio count matches. (Note: container duration can differ legitimately when a dropped track was longer — we hit a 10 s diff on a Mando remux from a long Russian track — so compare per-stream/video duration if tightening.)
  4. Move staged file next to original as `*.stripping`, then atomic `os.replace` over the original. chown 3000:3000.
  5. Log to `/tmp/remux_strip.log`.
- NASCinema should own the queue (DB table instead of text file) and call the same logic, or talk to the worker.

## 5. Performance notes
- HDD pool is RAIDZ1 (4×6TB, one SMR). Reading+writing the same HDD pool simultaneously thrashes (~1 GB/min, NAS sluggish). **Stage through the SSD** (`scratch` pool): HDD sequential read → SSD write → verify → SSD→HDD sequential write. Measured: Justice League 127 GB in 41.6 min total, JLU 125 GB in 34.7 min, NAS stayed responsive.
- One job at a time (parallel jobs thrash the HDDs).
- GTX 1050 is irrelevant here (stream copy, no transcode).

## 6. Lessons / gotchas from this session (don't repeat)
1. **Transmission stores the incomplete dir PER TORRENT** in `resume/*.resume` (bencoded `14:incomplete-dir21:/downloads/incomplete`). Changing global settings.json alone leaves existing torrents writing to the old path. If NASCinema ever relocates downloads, rewrite resume files (with correct bencode length prefixes) or use RPC set-location.
2. **Never delete an original until the replacement is verified AND in its final location.** Log every deletion (we use `/tmp/deletions.log`). An original vanished once during an unattended chain and the cause was never pinned down.
3. **Background jobs must not run inside a transient remote shell** — they died when the ADMS container restarted (Docker restart) and once with `ENOSYS` exec errors. Use `systemd-run --unit=... --property=Restart=on-failure`. (Transient units don't survive reboot — register in TrueNAS Init/Shutdown scripts if needed.)
4. `/tmp` on TrueNAS has `fs.protected_regular` — root cannot overwrite files in /tmp owned by another user. Keep job scripts in `/root/...`.
5. `pkill -f <pattern>` can kill your own shell if the pattern appears in the command line. Use `pgrep -f 'name[.]py'` style patterns or PIDs.
6. `/usr/local` is read-only on TrueNAS.
7. RuTracker filenames contain Cyrillic (e.g. `2004г`) — handle UTF-8 paths everywhere; Linux 255-byte filename limit can bite with long Cyrillic names (Transmission failed a torrent until neighbor files were renamed).
8. Resolution bug already found in NASCinema's quality scan: classifying by **height** mislabels 2.39:1 1080p (1920×800) as 720p — classify by **width**. Also add a separate "starved bitrate / YIFY-tier" flag (bitrate per minute + stereo AAC).

## 7. Nice-to-haves
- Show per-movie badges: "Lossless", "Atmos/DTS:X", "Foreign default audio ⚠", "Starved bitrate".
- Undo window: keep the pre-strip original on SSD for N hours before deleting (space permitting).
- Also handle TV episodes (same engine; JL/JLU/T&J were TV).
