# NASCinema — Claude Code project notes

Read automatically at session start. Keep machine/access facts here so I stop
guessing (e.g. defaulting to "Administrator").

## Machine access
Hostnames, IPs, usernames and SSH key paths are in **CLAUDE.local.md** (next to
this file, git-ignored — the repo is public). Claude Code loads it
automatically.

## Topology recap
NAS = backend (Docker `nascinema` :8400 + `nascinema-postgres`) and media;
GitHub (`simpson1045/NASCinema`, public) = source of truth + release builds;
the working copy is a local clone on the Mac; ELKO = renderer; ALPINE = not
part of building or deploying any more.

## Releases (GitHub Actions — never build on ALPINE)
Release builds on ALPINE froze it twice on 2026-09-26 (repo on a slow HDD +
Gradle; hard resets). Now:
**Versioning is earned (README rule 2) — most releases are build-only.**
- *Build-only* (fixes/polish Matt wants on the couch): keep the version, bump
  only the build number in `frontend/pubspec.yaml` (0.9.0+36 → 0.9.0+37), add
  the notes to the current `## 0.9.0` section of `CHANGELOG.md`, tag
  `v0.9.0-b37`. The updater compares build numbers, so every device updates.
- *Version* (a finished, meaningful feature set — ask Matt if unsure): bump
  X.Y.Z (+ build), new `## X.Y.Z - date` section, tag `vX.Y.Z`.
Never bump the version just to ship a build (0.5 → 0.9 in two days, 2026-09-26).

1. Update pubspec + CHANGELOG as above, commit, push.
2. `git tag <tag> && git push origin <tag>` → `.github/workflows/release.yml`
   builds Windows/Android/web on GitHub and publishes a GitHub Release (it
   checks the tag against pubspec version/build).
   Watch: `https://api.github.com/repos/simpson1045/NASCinema/actions/runs`.
3. On NASHOST: `sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" --release <tag>`
   (no restart).
Backend changes: **push to GitHub first**, then plain `deploy.sh` (pulls main
from GitHub, or `--ref <tag|sha>`, then restarts; records DEPLOYED_COMMIT).
`backend/release.bat` is the old ALPINE path — emergencies only.

> Passwords are NOT stored in this file (it's in git). The ALPINE→ELKO `net use`
> mapping is persisted, and start_mcp.bat re-establishes it.
