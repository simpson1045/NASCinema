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
- Build the Windows app on ALPINE (local disk), deploy the `Release` folder to
  `C:\NASCinema\renderer`. Once ELKO runs a build with the in-app updater
  (>= 0.3.8), future updates are in-app — no `C$` needed.

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
ALPINE = server (backend / PostgreSQL 17 / ffmpeg) **and** the Windows build host;
FRAMEWORK = dev box (no Visual Studio — can't build the Windows app);
ELKO = renderer; NAS = storage only.

> Passwords are NOT stored in this file (it's in git). The ALPINE→ELKO `net use`
> mapping is persisted, and start_mcp.bat re-establishes it.
