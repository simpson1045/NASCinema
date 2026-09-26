# NASCinema — Claude Code project notes

Read automatically at session start. Keep machine/access facts here so I stop
guessing (e.g. defaulting to "Administrator").

## Machine Access

### ELKO (192.168.0.19) — the renderer (wired to LG C2 + Denon)
- User: **matth** (NOT Administrator — ELKO has no usable Administrator account)
- Reach `C$` from ALPINE: `net use \\192.168.0.19\C$ /user:matth "<pw>" /persistent:yes`
  (start_mcp.bat connects as matth too). A `1909`/"locked out" or `C$`
  "does not exist" means a bad/stale **stored** credential — `cmdkey /list` to
  check, never assume Administrator.
- ELKO updates itself in-app (installed at `C:\NASCinema\renderer`) — no `C$`
  needed. Releases are built by GitHub Actions (see "Releases" below).

### NorthsideNAS (192.168.0.248) — storage
- SSH: `ssh -i C:\Users\matth\.ssh\nas_key root@192.168.0.248`
- Docker needs the full path: `/usr/local/bin/docker`
- Reach it by the **LAN IP `192.168.0.248`**, not the `NorthsideNAS` hostname
  (that resolves to a Tailscale IP → slow/flaky).

### PCREPS (100.98.16.50, via Tailscale)
- User: Administrator

### MCP service (ALPINE)
- NSSM service: `AlpineDevMCP`
- Runs as: `.\matth` (NOT LocalSystem)
- Port: 8849
- Backend commands run on ALPINE via the connector's `run_command`.

## Topology recap
NAS = backend (Docker `nascinema` :8400 + `nascinema-postgres`) and media;
ALPINE = the git checkout (`D:\Programming\NASCinema`, mounted on the Mac
over SMB) that `deploy.sh` pulls backend code from — **not a build machine any
more**; FRAMEWORK = dev box; ELKO = renderer.

## Releases (GitHub Actions — never build on ALPINE)
Release builds on ALPINE froze it twice on 2026-09-26 (repo on a slow HDD +
Gradle; hard resets). Now:
1. Set `version:` in `frontend/pubspec.yaml` (X.Y.Z+N), add `## X.Y.Z - date`
   notes at the top of `CHANGELOG.md`, commit, push.
2. `git tag vX.Y.Z && git push origin vX.Y.Z` → `.github/workflows/release.yml`
   builds Windows/Android/web on GitHub and publishes a GitHub Release.
   Watch: `https://api.github.com/repos/simpson1045/NASCinema/actions/runs`.
3. On NASHOST: `sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" --release vX.Y.Z`
   (no restart). Backend code changes still need a plain `deploy.sh` (restart).
`backend/release.bat` is the old ALPINE path — emergencies only.

> Passwords are NOT stored in this file (it's in git). The ALPINE→ELKO `net use`
> mapping is persisted, and start_mcp.bat re-establishes it.
