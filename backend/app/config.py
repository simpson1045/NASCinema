"""Application settings — everything is configuration, nothing hardcoded."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="NASCINEMA_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Server
    host: str = "0.0.0.0"
    port: int = 8400
    public_url: str = ""
    cors_origins: str = "*"

    # Security
    secret_key: str = "change-me-to-a-long-random-string"

    # Database (async psycopg3 driver)
    database_url: str = (
        "postgresql+psycopg://nascinema:nascinema@localhost:5432/nascinema"
    )

    # Media
    media_dirs: str = ""
    data_dir: Path = Path(".nascinema")
    # Persistent HLS transcode cache cap (GiB); LRU eviction. 0 = unlimited.
    transcode_cache_gb: float = 20.0
    # Video transcode backend: auto (GPU if a working NVENC is found, else CPU),
    # nvenc (force GPU), or cpu (force x264).
    transcode_hwaccel: str = "auto"
    # Where transcoded HLS segments live. Blank = <data_dir>/hls (local to the
    # app host). Point at a NAS share (UNC) to keep the cache off the host.
    cache_dir: str = ""

    # Integrations
    tmdb_api_key: str = ""
    opensubtitles_api_key: str = ""
    # OMDb (omdbapi.com) — optional; enables IMDB/Rotten Tomatoes/Metacritic
    # scores. Free key, 1k/day. Blank = those scores stay null.
    omdb_api_key: str = ""

    # FFmpeg overrides (auto-discovered when blank)
    ffmpeg: str = ""
    ffprobe: str = ""
    # yt-dlp for caching movie trailers (reused from NASRadio's setup).
    # Auto-discovered (PATH / C:\ytdl / common dirs) when blank.
    yt_dlp: str = ""
    # Where cached trailer MP4s live. Blank = <data_dir>/trailers.
    trailers_dir: str = ""
    # Max trailer resolution to cache. 2160 = grab 4K when it exists, else the
    # ladder falls to 1440p, then 1080p. VP9 (not AV1) so the Roku Ultra decodes
    # it; cached as MKV. Lower this if storage/bandwidth is a concern.
    trailer_max_height: int = 2160

    # Wired renderer (the theater PC). MAC enables POST /api/renderer/wake —
    # the phone wakes the sleeping renderer before "Play on <renderer>".
    # Blank = no wired renderer in this deployment. Get the MAC via `getmac`.
    renderer_mac: str = ""
    wol_broadcast: str = "255.255.255.255"

    # Extras DB (crowdsourced bonus-feature naming — see EXTRAS_DB.md).
    # Opt-in: fingerprint extras so they can later be matched/contributed.
    contribute_extras: bool = False
    fpcalc: str = ""  # Chromaprint binary; auto-discovered when blank

    @property
    def media_dir_list(self) -> list[str]:
        """Library folders, split on the OS path separator (';' on Windows)."""
        if not self.media_dirs.strip():
            return []
        return [p.strip() for p in self.media_dirs.split(os.pathsep) if p.strip()]

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
