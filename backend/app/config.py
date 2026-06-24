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

    # Integrations
    tmdb_api_key: str = ""

    # FFmpeg overrides (auto-discovered when blank)
    ffmpeg: str = ""
    ffprobe: str = ""

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
