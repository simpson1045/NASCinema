# NASCinema Extras DB

> A crowdsourced, fingerprint-keyed database of movie bonus features — "AcoustID/MusicBrainz for disc extras."

**Status: 🧪 design / groundwork.** This documents a separate service NASCinema feeds and queries. It is not built yet; NASCinema is starting to *collect* the data (see [Groundwork](#groundwork-in-nascinema)).

---

## The problem nobody has solved

When you rip a Blu-ray, the bonus features come off as `t10.mkv` / `SF_03_NE_04_Rapids.mkv` — the disc's menu *named* them, but the rip throws that away. Neither Plex nor Jellyfin can recover the names; both make you type them by hand. The reason isn't laziness:

> **One user's library has no way to know that `t10.mkv` is "Beyond Jurassic Park."** The mapping from an arbitrary local file to a real feature name is unsolvable from a single library.

But it is **trivially solvable once, by any one person, and then shareable to everyone.** That is exactly the shape of problem a crowdsourced database solves — and the slot for it is empty. MusicBrainz did it for albums, AcoustID for songs, TheTVDB for episodes. **Nothing exists for disc extras.**

## The insight: key on the audio fingerprint, not the filename

Filenames, file hashes, even UPCs are fragile — two people's rips of the same featurette differ in codec, resolution, filename, and exact bytes. But the **audio content is identical**. So:

- Compute a **Chromaprint** audio fingerprint (the AcoustID fingerprinter) of each extra.
- That fingerprint is **stable across re-encodes and rips** — your `t10.mkv` and my `Beyond.JP.mkv` of the same documentary produce matching fingerprints.
- The fingerprint becomes the **global key**. Map it to a name once; everyone benefits.

(The NAS family already has this DNA — NASRadio uses ShazamIO audio fingerprinting.)

## Architecture

```
NASCinema instance (per user)                Extras DB (central service)
  - fingerprints each extra (Chromaprint)
  - opt-in: submit {fingerprint, duration,    --submit-->   ingest + cluster fingerprints
            release/UPC, name, type}                        build consensus names
  - on scan: look up each fingerprint         <--lookup--    return consensus name/type/confidence
  - auto-names matched extras, flags the rest
```

## Identity & matching

A submission is keyed by **`fingerprint` + `duration`** (duration guards against fingerprint collisions on silent/music-only clips). Optional context that sharpens matching and grouping:
- **Release** — a Blu-ray.com release id or **UPC** (the exact pressing), so the same feature can be associated with the discs it appears on.
- **Disc fingerprint** — the multiset of all extra durations on a disc is itself a near-unique signature of a pressing.

## Data model (central service, sketch)

- `feature` — canonical entry: `id`, `consensus_title`, `consensus_type`, `confidence`.
- `fingerprint` — `chromaprint`, `duration`, `feature_id`.
- `submission` — `fingerprint`, `duration`, `release/upc`, `proposed_title`, `proposed_type`, `contributor`, `created_at`.
- `release` — `upc`, `bluray_url`, `title`, `year`, `edition`.

Consensus title/type = the most-agreed submission for a fingerprint cluster, weighted by contributor trust.

## API (sketch)

- `POST /submit` — `{fingerprint, duration, release?, upc?, title, type}` → `{accepted, feature_id}`
- `GET /lookup?fingerprint=…&duration=…` → `{title, type, confidence}` (or 404)
- `POST /lookup/batch` — many fingerprints at once (a whole movie's extras)
- API keys + rate limits.

## Consensus & moderation

MusicBrainz-style: multiple agreeing submissions raise confidence; edit history; trusted-contributor weighting; the ability to dispute/override. Auto-apply only above a confidence threshold; below it, NASCinema suggests rather than applies.

## Privacy & legal

**Metadata only — no content ever leaves the user.** Submissions carry a *fingerprint* (not the audio), a duration, and a name/type. This is the same legal posture as AcoustID. No file paths, no personal data. Opt-in, per instance.

## Cold start (the hard part) — and the unfair advantage

An empty database is worthless on day one. The flywheel:

1. NASCinema users already name extras in the **edit UI** — every such edit is a submission.
2. More NASCinema users → more mappings → better auto-naming → more reason to use NASCinema.
3. Seed pragmatically: pair user-supplied **names** (and durations) with the official **feature lists** humans read off Blu-ray.com.

The fuel is users, so **NASCinema's core has to grow first** — which is why the DB is sequenced after playback, with only lightweight collection starting now.

## Other hard problems

| Risk | Mitigation |
|---|---|
| Troll / wrong submissions | consensus + trust weighting + edit history |
| Fingerprint collisions (silence/music) | gate on `fingerprint + duration`; flag low-confidence |
| Hosting / scale / abuse | API keys, rate limits, caching, the service on dedicated infra |
| Re-encodes degrading fingerprints | Chromaprint is robust to transcoding; store multiple fingerprints per feature |

## Build phases

1. **Groundwork (in NASCinema, now):** fingerprint extras (Chromaprint) + an opt-in "contribute" switch; store fingerprints locally.
2. **Central service MVP:** submit + lookup API, fingerprint clustering, simple consensus.
3. **Auto-naming:** NASCinema batch-looks-up fingerprints on scan; auto-applies high-confidence names, suggests the rest in the edit UI.
4. **Community:** web front-end, contributor accounts, moderation, public API.

## Groundwork in NASCinema

The app computes a Chromaprint fingerprint per extra and stores it on `media_files.fingerprint`, gated by an opt-in (`NASCINEMA_CONTRIBUTE_EXTRAS`). Submission to the central service comes in phase 2 — but every fingerprint banked now is corpus the moment lookup exists.

---

*If this works, it's the first real database of disc bonus features in existence — and the thing every ripper has wanted for 20 years.*
