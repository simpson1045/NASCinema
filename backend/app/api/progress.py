"""Per-file playback progress — save where you left off + which subtitle was on,
so the next play (local or cast) resumes there."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models.watch_progress import WatchProgress

router = APIRouter(prefix="/api/progress", tags=["progress"])


class ProgressReq(BaseModel):
    position: float
    subtitle: str | None = None


@router.put("/{file_id}")
async def save_progress(
    file_id: int,
    req: ProgressReq,
    session: AsyncSession = Depends(get_session),
) -> dict:
    row = await session.scalar(
        select(WatchProgress).where(WatchProgress.media_file_id == file_id)
    )
    if row is None:
        row = WatchProgress(media_file_id=file_id)
        session.add(row)
    row.position_seconds = max(0.0, req.position)
    row.subtitle_id = req.subtitle or None
    await session.commit()
    return {"ok": True}


@router.get("/{file_id}")
async def get_progress(
    file_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    row = await session.scalar(
        select(WatchProgress).where(WatchProgress.media_file_id == file_id)
    )
    return {
        "position": row.position_seconds if row else 0.0,
        "subtitle": row.subtitle_id if row else None,
    }
