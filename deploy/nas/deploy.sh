#!/bin/bash
# Deploy NASCinema to the NAS. Run ON NASHOST:
#   sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" [--build | --release vX.Y.Z]
#
#   (none)            Backend code from ALPINE's checkout (over SSH; Windows'
#                     built-in tar streams it) into repo/, then restart.
#   --build           Same, and rebuild the image (requirements/Dockerfile).
#   --release vX.Y.Z  Publish an app release built by GitHub Actions
#                     (.github/workflows/release.yml): downloads the Windows zip,
#                     Android APK, web app and version.json from the GitHub
#                     Release. No restart.
#
# The apps are no longer built on ALPINE (release builds starved it, 2026-09-26),
# so a code deploy never touches backend/updates or the web app — those come
# only from a GitHub release. (--updates / --web: the old ALPINE-built path,
# kept for emergencies.) Nothing on ALPINE is modified.
set -euo pipefail

APP="/mnt/NAS Storage/apps/nascinema"
KEY="/mnt/NAS Storage/apps/adms/ssh/id_ed25519"
SRC="matth@192.168.0.150"
SRC_ROOT="D:/Programming/NASCinema"
GH_REPO="${NASCINEMA_GH_REPO:-simpson1045/NASCinema}"

# tar paths out of ALPINE's checkout, extracted into repo/.
pull() {
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$SRC" \
    "tar -cf - -C $SRC_ROOT --exclude=__pycache__ --exclude=.venv --exclude=.nascinema $*" \
    | tar -xf - -C "$APP/repo"
}

# App artifacts + changelog first, version.json LAST: clients poll it, so it
# must never advertise a build whose APK/zip is still being copied.
pull_updates() {
  pull --exclude=version.json backend/updates CHANGELOG.md
  pull backend/updates/version.json
}

mkdir -p "$APP/repo" "$APP/data"

if [[ "${1:-}" == "--release" ]]; then
  TAG="${2:?usage: deploy.sh --release vX.Y.Z}"
  BASE="https://github.com/$GH_REPO/releases/download/$TAG"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "[deploy] downloading release $TAG from GitHub…"
  for f in nascinema-windows.zip nascinema-android.apk nascinema-web.tar.gz version.json; do
    curl -fsSL --retry 3 -o "$TMP/$f" "$BASE/$f"
  done
  curl -fsSL --retry 3 -o "$TMP/CHANGELOG.md" \
    "https://raw.githubusercontent.com/$GH_REPO/$TAG/CHANGELOG.md"
  grep -q '"version"' "$TMP/version.json"   # sanity: a real version.json
  # Web app: unpack beside the live one, then swap (keep the last one as .prev).
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
  echo "[deploy] published $TAG:"
  curl -fs http://127.0.0.1:8400/api/update/check | head -c 300; echo
  exit 0
fi

if [[ "${1:-}" == "--web" ]]; then
  echo "[deploy] publishing the web app from ALPINE…"
  pull frontend/build/web
  chown -R 3000:3000 "$APP/repo/frontend/build/web" 2>/dev/null || true
  exit 0
fi

if [[ "${1:-}" == "--updates" ]]; then
  echo "[deploy] publishing app release from ALPINE…"
  pull_updates
  chown -R 3000:3000 "$APP/repo/backend/updates" "$APP/repo/CHANGELOG.md" 2>/dev/null || true
  curl -fs http://127.0.0.1:8400/api/update/check | head -c 300; echo
  exit 0
fi

echo "[deploy] pulling backend code from ALPINE…"
pull backend/app backend/alembic backend/alembic.ini backend/cast backend/requirements.txt backend/nascinema_run.py backend/Dockerfile backend/docker-entrypoint.sh
chmod +x "$APP/repo/backend/docker-entrypoint.sh"
chown -R 3000:3000 "$APP/repo" "$APP/data" 2>/dev/null || true

cd "$APP"
if [[ "${1:-}" == "--build" ]]; then
  docker compose up -d --build
else
  docker compose up -d
  docker restart nascinema >/dev/null
fi
echo "[deploy] waiting for health…"
# The NAS can take a few minutes to start under load — wait up to 3.
for i in $(seq 1 90); do
  if curl -fs http://127.0.0.1:8400/api/health >/dev/null; then
    echo "[deploy] OK — http://192.168.0.248:8400"
    exit 0
  fi
  sleep 2
done
echo "[deploy] backend did not become healthy; docker logs nascinema --tail 50:"
docker logs nascinema --tail 50
exit 1
