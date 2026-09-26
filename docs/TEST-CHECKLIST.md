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

