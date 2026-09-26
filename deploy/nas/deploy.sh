#!/bin/bash
# Deploy NASCinema on the NAS. Run ON the NAS host:
#   sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" [--build] [--ref REF]
#   sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" --release vX.Y.Z
#
#   (none)            Backend code from GitHub (branch main, or --ref <tag|branch|sha>)
#                     into repo/, then restart the container.
#   --build           Same, and rebuild the image (requirements/Dockerfile changes).
#   --release vX.Y.Z  Publish an app release built by GitHub Actions
#                     (.github/workflows/release.yml): the Windows zip, Android APK,
#                     web app and version.json from the GitHub Release. No restart.
#
# GitHub is the source of truth: push first, then deploy. Nothing is built or
# pulled from a home PC any more (release builds starved the Windows build box,
# 2026-09-26). --updates / --web are the old path (copy from a Windows checkout
# over SSH) kept for emergencies; they read ALPINE_SRC / ALPINE_KEY /
# ALPINE_ROOT from deploy.env next to this script (not in the repo).
set -euo pipefail

APP="/mnt/NAS Storage/apps/nascinema"
GH_REPO="${NASCINEMA_GH_REPO:-simpson1045/NASCinema}"
[ -f "$APP/deploy.env" ] && . "$APP/deploy.env"

# Backend files a code deploy ships (the apps come only from --release).
CODE_PATHS=(backend/app backend/alembic backend/alembic.ini backend/cast
            backend/requirements.txt backend/nascinema_run.py backend/Dockerfile
            backend/docker-entrypoint.sh)

mkdir -p "$APP/repo" "$APP/data"

MODE=code
REF=main
REL_TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build) MODE=build ;;
    --ref) REF="${2:?--ref needs a value}"; shift ;;
    --release) MODE=release; REL_TAG="${2:?usage: deploy.sh --release vX.Y.Z}"; shift ;;
    --updates) MODE=updates ;;
    --web) MODE=web ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- app release from GitHub -----------------------------------------------------
if [ "$MODE" = release ]; then
  BASE="https://github.com/$GH_REPO/releases/download/$REL_TAG"
  echo "[deploy] downloading release $REL_TAG from GitHub…"
  for f in nascinema-windows.zip nascinema-android.apk nascinema-web.tar.gz version.json; do
    curl -fsSL --retry 3 -o "$TMP/$f" "$BASE/$f"
  done
  curl -fsSL --retry 3 -o "$TMP/CHANGELOG.md" \
    "https://raw.githubusercontent.com/$GH_REPO/$REL_TAG/CHANGELOG.md"
  grep -q '"version"' "$TMP/version.json"   # sanity: a real version.json
  # Web app: unpack beside the live one, then swap (the last one kept as .prev).
  mkdir -p "$TMP/web" "$APP/repo/frontend/build"
  tar -xzf "$TMP/nascinema-web.tar.gz" -C "$TMP/web"
  B="$APP/repo/frontend/build"
  rm -rf "$B/web.new" && cp -a "$TMP/web" "$B/web.new"
  rm -rf "$B/web.prev"; [ -d "$B/web" ] && mv "$B/web" "$B/web.prev"
  mv "$B/web.new" "$B/web"
  # App packages + changelog first, version.json LAST: clients poll it, so it
  # must never advertise a build whose APK/zip is still being copied.
  U="$APP/repo/backend/updates"
  mkdir -p "$U"
  for f in nascinema-windows.zip nascinema-android.apk; do
    cp "$TMP/$f" "$U/$f.part" && mv "$U/$f.part" "$U/$f"
  done
  cp "$TMP/CHANGELOG.md" "$APP/repo/CHANGELOG.md"
  cp "$TMP/version.json" "$U/version.json.part" && mv "$U/version.json.part" "$U/version.json"
  chown -R 3000:3000 "$B/web" "$U" "$APP/repo/CHANGELOG.md" 2>/dev/null || true
  echo "[deploy] published $REL_TAG:"
  curl -fs http://127.0.0.1:8400/api/update/check | head -c 300; echo
  exit 0
fi

# --- emergency: copy from a Windows checkout over SSH -------------------------------
if [ "$MODE" = updates ] || [ "$MODE" = web ]; then
  : "${ALPINE_SRC:?set ALPINE_SRC (user@host) in $APP/deploy.env}"
  : "${ALPINE_KEY:?set ALPINE_KEY in $APP/deploy.env}"
  : "${ALPINE_ROOT:=D:/Programming/NASCinema}"
  pull() {
    ssh -i "$ALPINE_KEY" -o StrictHostKeyChecking=accept-new "$ALPINE_SRC" \
      "tar -cf - -C $ALPINE_ROOT --exclude=__pycache__ --exclude=.venv --exclude=.nascinema $*" \
      | tar -xf - -C "$APP/repo"
  }
  if [ "$MODE" = web ]; then
    pull frontend/build/web
  else
    pull --exclude=version.json backend/updates CHANGELOG.md
    pull backend/updates/version.json
  fi
  chown -R 3000:3000 "$APP/repo" 2>/dev/null || true
  exit 0
fi

# --- backend code from GitHub + restart ---------------------------------------------
SHA=$(curl -fsSL "https://api.github.com/repos/$GH_REPO/commits/$REF" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
echo "[deploy] backend code from GitHub $GH_REPO @ $REF (${SHA:0:7})…"
curl -fsSL --retry 3 "https://codeload.github.com/$GH_REPO/tar.gz/$SHA" | tar -xz -C "$TMP"
SRC_DIR=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)
for p in "${CODE_PATHS[@]}"; do
  if [ -d "$SRC_DIR/$p" ]; then
    mkdir -p "$APP/repo/$p" && cp -a "$SRC_DIR/$p/." "$APP/repo/$p/"
  else
    mkdir -p "$(dirname "$APP/repo/$p")" && cp -a "$SRC_DIR/$p" "$APP/repo/$p"
  fi
done
echo "$SHA $REF $(date -u +%FT%TZ)" > "$APP/repo/DEPLOYED_COMMIT"
chmod +x "$APP/repo/backend/docker-entrypoint.sh"
chown -R 3000:3000 "$APP/repo" "$APP/data" 2>/dev/null || true

cd "$APP"
if [ "$MODE" = build ]; then
  docker compose up -d --build
else
  docker compose up -d
  docker restart nascinema >/dev/null
fi
echo "[deploy] waiting for health…"
# The NAS can take a few minutes to start under load — wait up to 3.
for i in $(seq 1 90); do
  if curl -fs http://127.0.0.1:8400/api/health >/dev/null; then
    echo "[deploy] OK — backend ${SHA:0:7} healthy on :8400"
    exit 0
  fi
  sleep 2
done
echo "[deploy] backend did not become healthy; docker logs nascinema --tail 50:"
docker logs nascinema --tail 50
exit 1
