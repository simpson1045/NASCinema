# Bundled mpv config (Windows renderer)

Shipped next to `nascinema.exe` (CMake installs this folder into the build) and
passed to the native mpv player with `--config-dir`. It gives the movie player
its on-video UI — mpv's own window is native airspace, so no Flutter UI can be
drawn over the video; only mpv scripts can.

| Component | Version | Source | License |
|---|---|---|---|
| uosc (on-screen controls, menus) | 5.13.0 | https://github.com/tomasklaen/uosc | LGPL-2.1 (`licenses/`) |
| thumbfast (seek-bar thumbnails) | master @ 2026-08-12 | https://github.com/po5/thumbfast | MPL-2.0 (`licenses/`) |

Only the Windows `ziggy` helper binary is kept (uosc's darwin/linux builds are
dropped). NASCinema's own settings live in `mpv.conf` and `script-opts/*.conf`
(themed: navy + Blockbuster amber). To update uosc: replace `scripts/uosc` and
`fonts/` from a release zip, keep our `script-opts/uosc.conf`.
