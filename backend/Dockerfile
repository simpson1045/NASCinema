# NASCinema backend — runs on the NAS as a plain Docker container.
# Code is bind-mounted over /srv/nascinema by docker-compose (edit -> restart,
# no rebuild); the COPY below only makes the image self-contained as a fallback.
# Rebuild only when requirements.txt or this file change.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# ffmpeg/ffprobe (stream copy, audio-only transcode, HLS), Chromaprint fpcalc
# (Extras DB fingerprints). No GPU here on purpose — video is never transcoded.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg libchromaprint-tools ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/nascinema/backend
COPY requirements.txt .
RUN pip install -r requirements.txt yt-dlp

COPY . /srv/nascinema/backend
RUN chmod +x /srv/nascinema/backend/docker-entrypoint.sh

EXPOSE 8400
ENTRYPOINT ["/srv/nascinema/backend/docker-entrypoint.sh"]
