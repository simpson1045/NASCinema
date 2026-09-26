"""One Track Manager strip: a queued/running/finished rewrite of one file.

The API (read-only on the library) creates rows and sets `request`; the strip
worker (app/strip_worker.py — the only process with write access to the
movies) does the work and the undo/confirm requests. See
docs/SPEC-track-manager.md.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Float, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from ..db import Base


class StripJob(Base):
    __tablename__ = "strip_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    media_file_id: Mapped[int] = mapped_column(Integer, index=True)
    movie_id: Mapped[int | None] = mapped_column(Integer)
    path: Mapped[str] = mapped_column(String(1024))
    # queued | running | done | failed | skipped | cancelled | undone | confirmed
    status: Mapped[str] = mapped_column(String(16), index=True, default="queued")
    # While running: staging | verifying | placing.
    phase: Mapped[str | None] = mapped_column(String(16))
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    # Set by the API, carried out by the worker: "undo" | "confirm".
    request: Mapped[str | None] = mapped_column(String(16))
    error: Mapped[str | None] = mapped_column(Text)
    savings_est: Mapped[int | None] = mapped_column(BigInteger)
    original_bytes: Mapped[int | None] = mapped_column(BigInteger)
    new_bytes: Mapped[int | None] = mapped_column(BigInteger)
    # The untouched original, renamed next to the stripped file until Matt
    # presses "Confirm & free space" (or Undo puts it back).
    pre_strip_path: Mapped[str | None] = mapped_column(String(1024))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
