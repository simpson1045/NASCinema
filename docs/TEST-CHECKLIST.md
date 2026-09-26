# NASCinema — test checklist

Everything built since the last hands-on test session, so it can be tested in
one sitting. Each item says what to do, what "working" looks like, and what
Claude could NOT verify without the TV. Tick items off (or press **View** to
flag anything wrong — flags record the screen, movie, time and a screenshot).

Legend: 🖥️ ELKO (Big Picture) · 📺 Roku · ✅ verified by Claude (tests/renders/API) · 👀 needs eyes on the TV

---

## Shipped, not yet tested by Matt

### Player (ELKO)
- [ ] 👀 **On-screen controls** (uosc, navy + gold): move the mouse or press ▲/▼ mid-movie → title bar, gold timeline, chapter marks, time left appear and fade.
- [ ] 👀 **Scrub thumbnails:** hover/scrub the timeline → preview images.
- [ ] 👀 **Button legend** ~2.5 s after a movie starts, and on ▲/▼ — real Xbox glyphs (green A, red B, blue X, yellow Y) drawn over the video.
- [ ] 👀 **Controller:** A pause · ◀▶ ±10 s · LB/RB chapter · X audio menu · Y subtitle menu · Start menu · B back · View flag.
- [ ] 👀 **Versions mid-movie:** ▼ (or the Versions button on the bar) → pick another cut → reloads at the same moment, same language (ANH: 4K remux ↔ 4K77 ↔ Harmy).

### Versions / audio / subtitles picker (ELKO)
- [ ] ✅👀 **Movie page → "Versions & Audio"** → full-screen picker. ANH: choose 4K77 → "1.0 DTS-HD-MA (1977 35mm mono mix)" (LOSSLESS) → Subtitles Off → Play starts exactly that.
- [ ] 👀 Pick is **remembered** next time you open the movie.
- [ ] 👀 **Logo centred** over the summary line at the top of the picker.
- [ ] 👀 Subtitles: movies without a forced track start **Off** (no "Automatic"); ones with a forced track show "Automatic — Shows '…' for foreign-language scenes".

### Trailers
- [ ] 👀 **Apple trailers** everywhere (sharper, 5.1); 480p-only Apple titles use YouTube HD instead.
- [ ] 👀 **Trailer button** (movie page): SDR trailers play in-app with the overlay (title, gold progress bar, times) — A pause · ◀▶ skip · B back; other buttons don't close it.
- [ ] 👀 **HDR trailers** (Elf, Christmas Vacation, LOTR, Naked Gun 33⅓, Airplane II, Sherlock 2): with Settings → HDR trailers = Auto and Windows HDR on, the Trailer button plays through the HDR player (TV switches to HDR), controller works.
- [ ] 👀 Settings → **HDR trailers** selector is gold; "Right now: HDR is on for this display".

### Home / hero
- [ ] 👀 **Logos centred** over the year · rating · IMDb · RT · quality row — home hero, fullscreen hero, movie page (ELKO) and Roku (home + fullscreen, channel 0.1.11).
- [ ] ✅👀 **Content ratings** (PG, PG-13, R …) badge after the year everywhere.
- [ ] 👀 **Sequel logos:** The Land Before Time VIII shows the series logo + gold "VIII · The Big Freeze"; LBT II shows its own logo.

### Other
- [ ] 👀 **Mouse cursor** hides when the controller/keyboard is used, returns on mouse move.
- [ ] 👀 **Flag button:** View (or F8) anywhere → "Flagged ✓".
- [ ] 📺 Roku 0.1.11 sideloaded (zip in Mac ~/Downloads): HDR trailers on an HDR TV, centred logos, rating badge.

---

## Batch 1 (in progress)

### Search (ELKO Big Picture) — ✅ tests (matching rules, keyboard typing)
- [ ] 👀 Home shows **"Y Search · Menu"** hints top-right (hidden in fullscreen hero).
- [ ] 👀 **Y** opens search: on-screen keyboard left, results right. D-pad around the keys; → off the right edge jumps into results, ← from the first result column comes back.
- [ ] 👀 **A** types / opens a movie · **X** delete · **Y** space · **B** back. A real keyboard types directly (Backspace, Esc too).
- [ ] 👀 "potter" → all 8 Harry Potters; "jur park" → Jurassic Park films; "rocky" → the Rocky films, most popular first.
- [ ] 👀 Opening a result → movie page → Back returns to search with the query intact.

### Franchises (ELKO Big Picture + backend) — ✅ analyze/tests/render of the row
- [ ] 👀 Home has a **Franchises** row right after Continue Watching (or first): wide tiles with each franchise's logo over a backdrop, name + "N movies · years" below.
- [ ] 👀 **Animated tile:** highlight one → it grows, the backdrop slowly pans/zooms and crossfades through that franchise's movies every ~4 s; moving off stops it. Smooth, no stutter in the hero trailer above.
- [ ] 👀 While on the Franchises row the hero keeps its featured rotation (doesn't follow).
- [ ] 👀 **A** on a tile → franchise page: backdrop, logo **centred over** "8 movies · 2001–2011", overview, posters in release order (year above title). ◀▶ browse · A open · B back.
- [ ] 👀 Movie page (e.g. any Harry Potter): bottom band shows **"More in Harry Potter · 8"** — 16:9 cards, this movie tagged NOW VIEWING. ▼ into it, ◀▶ browse, A opens another; ▼ again switches the band to Extras, ▲ back.
- [ ] 👀 Franchise logos/backdrops look right (TMDB collection art) — note any wrong/missing ones.

### Movie page: Cast + More like this (ELKO) — ✅ analyze/tests
- [ ] 👀 Bottom band steps with ▼/▲ through **More in <series> → More like this → Cast → Extras** (only the rows that exist; on the Play buttons it previews the first one).
- [ ] 👀 **More like this** shows only movies in your library (TMDB recommendations, topped up with same-genre movies) — never the movie itself or its own franchise. A opens one.
- [ ] 👀 **Cast**: round headshots, name, character, top-billed first (browse only for now).
- [ ] 👀 Page opens fast — cast/more-like-this fill in a moment after.

### My List (ELKO + backend) — ✅ analyze/tests, real-font render (buttons fit)
- [ ] 👀 Movie page has a round **+** button after Versions & Audio; highlighted it says "Add to My List". A → toast "Added to My List", icon becomes ✓ ("On My List — A to remove"). A again removes.
- [ ] 👀 Home shows a **My List** row right after Continue Watching (newest first) once something's on it.

### Online subtitles (ELKO picker) — ✅ analyze/tests (pick carries a download)
- [ ] 👀 Picker → Subtitles column ends with **"Search online…"** → results screen (release names, SDH/TRUSTED tags, download counts). ▲▼ + A downloads → back in the picker with **"Downloaded · EN"** selected; Play shows it (embedded subs off).
- [ ] 👀 Reopen the picker: the download is listed for that version; switching versions shows that version's downloads instead.
- [ ] 👀 Subtitle sync is right (hash matches should be exact; title-only matches may drift — say which movie).


## Batch 2 — Roku 0.2.1 (sideload ~/Downloads/NASCinema-roku.zip) — ✅ brighterscript lint (CI)

### Movie page
- [ ] 👀 OK on any poster **or the hero** opens a movie page (no more instant play): backdrop, logo centered over the rating row, overview, then a line like "4K HDR · Audio: Auto · Subtitles: Off".
- [ ] 👀 Sequel line under a franchise logo ("VIII · The Big Freeze") on the movie page **and** the home hero (both home and fullscreen), centered with the logo.
- [ ] 👀 Buttons: **Play** (or **Resume 1:02:13** + **Play from start** if you've watched part of it), **Audio & Subtitles**, **+ My List**. ◀▶ moves, OK presses, Back returns home to where you were.
- [ ] 👀 + My List ⇄ On My List toggles (and shows up in the ELKO app's My List row).

### The * key (options panel)
- [ ] 👀 * on the movie page (or the Audio & Subtitles button) opens a right-hand panel: VERSION (if more than one), AUDIO (Auto + every track), SUBTITLES (Off + every track + downloaded ones), Flag a problem.
- [ ] 👀 TrueHD / DTS-HD audio and PGS subtitles are **greyed "(ELKO app)"** and the cursor skips them.
- [ ] 👀 Pick an audio track + subtitle, Back, Play → it plays with those (check the Denon's display for the audio format).
- [ ] 👀 **During playback** * opens the same panel (if Roku's own menu pops up instead, tell me — that's the one unknown). Subtitles switch live; changing audio/version restarts at the same spot in a second or two.
- [ ] 👀 Downloaded (OpenSubtitles) subtitles from the ELKO app show on the Roku and are in sync.
- [ ] 👀 Flag a problem (home, movie page, mid-movie) → toast "Flag sent — thanks"; it shows in the flags list with platform "roku".

### Resume
- [ ] 👀 Watch a few minutes, Back → the page now says **Resume <time>**; Resume picks up there. Same position shows in the ELKO app's Continue Watching.
- [ ] 👀 Finish a movie (or stop in the last 5%) → back to plain **Play**.

### Franchises (Roku)
- [ ] 👀 Home has a **Franchises** row (first row, or right after Continue Watching): wide cards with the franchise backdrop and its logo centered on it; name instead of a logo for Batman (DC Animated), Almighty, Jump Street, Peanuts. Label underneath "Harry Potter · 8 movies".
- [ ] 👀 OK on a card → franchise page: logo centered over "8 movies · 2001–2011", overview, posters in release order. OK on a poster → its movie page; **Back returns to the franchise page**, Back again → home.
- [ ] 👀 * on the franchise page → Flag a problem.
