"""Couch-side problem reports. The app POSTs one when Matt presses the
controller's View button (or F8); Claude reads the open ones each session
and resolves them with a note."""

from __future__ import annotations

import base64
import binascii
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_session
from ..models.flag import Flag

router = APIRouter(prefix="/api/flags", tags=["flags"])


def _flags_dir() -> Path:
    d = get_settings().data_dir / "flags"
    d.mkdir(parents=True, exist_ok=True)
    return d


class FlagReq(BaseModel):
    app_version: str | None = None
    platform: str | None = None
    screen: str | None = None
    kind: str | None = None
    movie_id: int | None = None
    movie_title: str | None = None
    media_file_id: int | None = None
    position_seconds: float | None = None
    note: str | None = None
    context: dict | None = None
    screenshot_png_b64: str | None = None


class ResolveReq(BaseModel):
    resolved: bool = True
    resolution_note: str | None = None


def _out(f: Flag) -> dict:
    return {
        "id": f.id,
        "created_at": f.created_at.isoformat() if f.created_at else None,
        "app_version": f.app_version,
        "platform": f.platform,
        "screen": f.screen,
        "kind": f.kind,
        "movie_id": f.movie_id,
        "movie_title": f.movie_title,
        "media_file_id": f.media_file_id,
        "position_seconds": f.position_seconds,
        "note": f.note,
        "context": f.context,
        "screenshot": f"/api/flags/{f.id}/screenshot" if f.has_screenshot else None,
        "resolved": f.resolved,
        "resolution_note": f.resolution_note,
    }


@router.post("")
async def create_flag(req: FlagReq, session: AsyncSession = Depends(get_session)) -> dict:
    f = Flag(**req.model_dump(exclude={"screenshot_png_b64"}))
    session.add(f)
    await session.flush()
    if req.screenshot_png_b64:
        try:
            png = base64.b64decode(req.screenshot_png_b64, validate=True)
            (_flags_dir() / f"{f.id}.png").write_bytes(png)
            f.has_screenshot = True
        except (binascii.Error, ValueError, OSError):
            pass  # the flag itself matters more than its picture
    await session.commit()
    return _out(f)


@router.get("")
async def list_flags(
    open_only: bool = True, session: AsyncSession = Depends(get_session)
) -> list[dict]:
    q = select(Flag).order_by(Flag.created_at.desc())
    if open_only:
        q = q.where(Flag.resolved.is_(False))
    return [_out(f) for f in (await session.scalars(q)).all()]


@router.get("/{flag_id}/screenshot")
async def flag_screenshot(flag_id: int) -> FileResponse:
    p = _flags_dir() / f"{flag_id}.png"
    if not p.exists():
        raise HTTPException(404, "no screenshot")
    return FileResponse(p, media_type="image/png")


@router.patch("/{flag_id}")
async def resolve_flag(
    flag_id: int, req: ResolveReq, session: AsyncSession = Depends(get_session)
) -> dict:
    f = await session.get(Flag, flag_id)
    if f is None:
        raise HTTPException(404, "no such flag")
    f.resolved = req.resolved
    if req.resolution_note is not None:
        f.resolution_note = req.resolution_note
    await session.commit()
    return _out(f)
