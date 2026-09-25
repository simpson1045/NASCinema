#!/bin/bash
# Deploy NASCinema to the NAS. Run ON NASHOST:
#   sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" [--build | --updates | --web]
# Pulls backend + cast + built web app from ALPINE's D: over SSH (Windows'
# built-in tar streams it), drops them in repo/, then restarts the container.
# --build also rebuilds the image (needed after requirements.txt/Dockerfile
# changes). --updates publishes an app release only (backend/updates +
# CHANGELOG.md from backend\release.bat) with no restart; --web publishes
# frontend/build/web only, no restart. Nothing on ALPINE
# is modified.
set -euo pipefail

APP="/mnt/NAS Storage/apps/nascinema"
KEY="/mnt/NAS Storage/apps/adms/ssh/id_ed25519"
SRC="matth@192.168.0.150"
SRC_ROOT="D:/Programming/NASCinema"

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

echo "[deploy] pulling code from ALPINE…"
pull backend/app backend/alembic backend/alembic.ini backend/cast backend/requirements.txt backend/nascinema_run.py backend/Dockerfile backend/docker-entrypoint.sh frontend/build/web
pull_updates
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
for i in $(seq 1 30); do
  if curl -fs http://127.0.0.1:8400/api/health >/dev/null; then
    echo "[deploy] OK — http://192.168.0.248:8400"
    exit 0
  fi
  sleep 2
done
echo "[deploy] backend did not become healthy; docker logs nascinema --tail 50:"
docker logs nascinema --tail 50
exit 1
