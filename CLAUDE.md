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
1. Set `version:` in `frontend/pubspec.yaml` (X.Y.Z+N), add `## X.Y.Z - date`
   notes at the top of `CHANGELOG.md`, commit, push.
2. `git tag vX.Y.Z && git push origin vX.Y.Z` → `.github/workflows/release.yml`
   builds Windows/Android/web on GitHub and publishes a GitHub Release.
   Watch: `https://api.github.com/repos/simpson1045/NASCinema/actions/runs`.
3. On NASHOST: `sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" --release vX.Y.Z`
   (no restart).
Backend changes: **push to GitHub first**, then plain `deploy.sh` (pulls main
from GitHub, or `--ref <tag|sha>`, then restarts; records DEPLOYED_COMMIT).
`backend/release.bat` is the old ALPINE path — emergencies only.

> Passwords are NOT stored in this file (it's in git). The ALPINE→ELKO `net use`
> mapping is persisted, and start_mcp.bat re-establishes it.
