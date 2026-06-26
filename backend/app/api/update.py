"""In-app update: version manifest + per-platform artifact download.

The release script (`backend/release.bat`) builds the apps, drops the artifacts
into `backend/updates/`, and writes `version.json`. Clients poll `/check`,
compare against their own PackageInfo, and pull `/download/<platform>`.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

router = APIRouter(prefix="/api/update", tags=["update"])

# backend/  (parents: api -> app -> backend)
_BASE_DIR = Path(__file__).resolve().parents[2]
_UPDATES_DIR = _BASE_DIR / "updates"
_CHANGELOG = _BASE_DIR.parent / "CHANGELOG.md"  # repo root

_ARTIFACTS = {
    "android": "nascinema-android.apk",
    "windows": "nascinema-windows.zip",
    "linux": "nascinema-linux.tar.xz",
}


def _read_version() -> dict | None:
    path = _UPDATES_DIR / "version.json"
    if not path.exists():
        return None
    # utf-8-sig tolerates a BOM (PowerShell's UTF8 writes one; json chokes on it).
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _latest_changelog() -> str:
    """Return the first '## ' section of CHANGELOG.md (the newest release)."""
    if not _CHANGELOG.exists():
        return ""
    content = _CHANGELOG.read_text(encoding="utf-8-sig")
    for section in re.split(r"(?=^## )", content, flags=re.MULTILINE):
        section = section.strip()
        if section.startswith("## "):
            return section
    return ""


@router.get("/check")
async def check_update() -> dict:
    v = _read_version()
    if not v:
        raise HTTPException(status_code=404, detail="No version info available")
    return {
        "status": "ok",
        "version": v.get("version", "0.0.0"),
        "build_number": v.get("build_number", 0),
        "changelog": _latest_changelog(),
        "android_size": v.get("android_size", 0),
        "windows_size": v.get("windows_size", 0),
        "linux_size": v.get("linux_size", 0),
        "released_at": v.get("released_at", ""),
    }


@router.get("/download/{platform}")
async def download_update(platform: str):
    name = _ARTIFACTS.get(platform)
    if not name:
        raise HTTPException(status_code=400, detail="Invalid platform")
    path = _UPDATES_DIR / name
    if not path.exists():
        raise HTTPException(
            status_code=404, detail=f"No update file available for {platform}"
        )
    # FileResponse honours Range, so the download is resumable.
    return FileResponse(path, filename=name, media_type="application/octet-stream")
