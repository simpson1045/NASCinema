"""Track Manager strip worker — `python -m app.strip_worker`.

Runs in its own container (nascinema-strip), the only one that mounts the
movies read-write. One job at a time (parallel jobs thrash the HDD pool),
oldest first; Undo / Confirm requests from the app are handled between jobs.
While the NAS is busy (1-minute load above strip_max_load) it waits before
starting the next job. Writes a heartbeat to <data_dir>/strip_worker.json so
the app can tell it's alive.
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path

from sqlalchemy import select, text

from .config import get_settings
from .db import SessionLocal
from .models import StripJob
from .strip import handle_requests, log, recover, run_job


def _beat(**state) -> None:
    try:
        p = Path(get_settings().data_dir) / "strip_worker.json"
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps({"ts": time.time(), "load": os.getloadavg()[0], **state}))
        os.replace(tmp, p)
    except OSError:
        pass


async def _wait_for_table() -> None:
    # The main container runs the migrations; wait for strip_jobs to exist.
    while True:
        try:
            async with SessionLocal() as s:
                await s.execute(text("SELECT 1 FROM strip_jobs LIMIT 1"))
            return
        except Exception as e:
            print(f"[strip-worker] waiting for the database ({e.__class__.__name__})", flush=True)
            await asyncio.sleep(5)


async def _next_job() -> int | None:
    async with SessionLocal() as s:
        return await s.scalar(select(StripJob.id).where(StripJob.status == "queued")
                              .order_by(StripJob.id).limit(1))


async def main() -> None:
    await _wait_for_table()
    await recover()
    log("strip worker up")
    max_load = get_settings().strip_max_load
    waiting = False
    while True:
        await handle_requests()
        job_id = await _next_job()
        load = os.getloadavg()[0]
        if job_id and load > max_load:
            if not waiting:
                log(f"waiting — NAS load {load:.1f} > {max_load}")
            waiting = True
            _beat(state="waiting_for_load")
            await asyncio.sleep(30)
            continue
        waiting = False
        if job_id:
            # Keep beating (and answering Undo/Confirm for other jobs) while a
            # long strip runs.
            task = asyncio.create_task(run_job(job_id))
            while not task.done():
                _beat(state="working", job=job_id)
                await asyncio.wait({task}, timeout=15)
                await handle_requests()
            await task
        else:
            _beat(state="idle")
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(main())
