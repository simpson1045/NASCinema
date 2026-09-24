#!/bin/sh
# Wait for Postgres, apply migrations, serve. Runs from /srv/nascinema/backend.
set -e
cd /srv/nascinema/backend
python - <<'PY'
import os, sys, time
import psycopg
url = os.environ["NASCINEMA_DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://")
for i in range(60):
    try:
        psycopg.connect(url, connect_timeout=3).close()
        sys.exit(0)
    except Exception as e:
        print(f"[entrypoint] waiting for postgres ({e.__class__.__name__})", flush=True)
        time.sleep(2)
sys.exit("postgres never came up")
PY
python -m alembic upgrade head
exec python nascinema_run.py "$@"
