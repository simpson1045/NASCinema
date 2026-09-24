#!/bin/bash
# Deploy NASCinema to the NAS. Run ON NASHOST:
#   sudo bash "/mnt/NAS Storage/apps/nascinema/deploy.sh" [--build]
# Pulls backend + cast + built web app from ALPINE's D: over SSH (Windows'
# built-in tar streams it), drops them in repo/, then restarts the container.
# --build also rebuilds the image (needed after requirements.txt/Dockerfile
# changes). Nothing on ALPINE is modified.
set -euo pipefail

APP="/mnt/NAS Storage/apps/nascinema"
KEY="/mnt/NAS Storage/apps/adms/ssh/id_ed25519"
SRC="matth@192.168.0.150"
SRC_ROOT="D:/Programming/NASCinema"

mkdir -p "$APP/repo" "$APP/data"
echo "[deploy] pulling code from ALPINE…"
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$SRC" \
  "tar -cf - -C $SRC_ROOT --exclude=__pycache__ --exclude=.venv --exclude=.nascinema backend/app backend/alembic backend/alembic.ini backend/cast backend/updates backend/requirements.txt backend/nascinema_run.py backend/Dockerfile backend/docker-entrypoint.sh frontend/build/web" \
  | tar -xf - -C "$APP/repo"
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
