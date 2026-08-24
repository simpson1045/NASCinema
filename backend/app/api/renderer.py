"""Renderer power control — Wake-on-LAN for the wired theater PC.

The couch flow: the renderer sleeps (~2 W); "Play on <renderer>" from a phone
first hits this endpoint, the magic packet wakes the PC, the app launches at
logon, playback follows. The MAC/broadcast live in server config
(NASCINEMA_RENDERER_MAC / NASCINEMA_WOL_BROADCAST) — nothing hardcoded, and a
deployment without a wired renderer simply leaves the MAC blank (404 here).
"""

from __future__ import annotations

import re
import socket

from fastapi import APIRouter, HTTPException

from ..config import get_settings

router = APIRouter(prefix="/api/renderer", tags=["renderer"])


def _magic_packet(mac: str) -> bytes:
    clean = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(clean) != 12:
        raise ValueError(f"bad MAC {mac!r}")
    hw = bytes.fromhex(clean)
    return b"\xff" * 6 + hw * 16


@router.post("/wake")
async def wake_renderer() -> dict:
    s = get_settings()
    if not s.renderer_mac.strip():
        raise HTTPException(404, "no renderer MAC configured (NASCINEMA_RENDERER_MAC)")
    try:
        packet = _magic_packet(s.renderer_mac)
    except ValueError as e:
        raise HTTPException(500, str(e)) from e
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        # Send a small burst — WOL is fire-and-forget UDP; NICs coming out of
        # low-power link states can miss a lone packet.
        for _ in range(3):
            sock.sendto(packet, (s.wol_broadcast, 9))
    finally:
        sock.close()
    return {"ok": True, "mac": s.renderer_mac, "broadcast": s.wol_broadcast}
