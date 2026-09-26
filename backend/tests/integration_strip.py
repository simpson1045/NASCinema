"""End-to-end test of app/strip.py on synthetic 60-second files — strip,
undo, strip + confirm, already clean, damaged file, crash mid-swap, fan
preservation. Needs ffmpeg + the database, so it runs in a throwaway
container on the NAS with a scratch dir as /t and a staging dir as /stage —
never the library:

  docker run --rm --network host --env-file .env \
    -e NASCINEMA_DATABASE_URL=... -e NASCINEMA_DATA_DIR=/t/data \
    -e NASCINEMA_STRIP_DIR=/stage -v "$APP/repo:/srv/nascinema:ro" \
    -v $T:/t -v $T/stage:/stage --entrypoint python nascinema:latest \
    /srv/nascinema/backend/tests/integration_strip.py

Its StripJob rows are deleted at the end.
"""
import asyncio, hashlib, json, os, subprocess, sys

sys.path.insert(0, "/srv/nascinema/backend")
from sqlalchemy import delete  # noqa: E402
from app import strip  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import StripJob  # noqa: E402
from app.probe import probe_file  # noqa: E402

T, STAGE = "/t", "/stage"
results = []


def check(name, cond, info=""):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name + (f"  [{info}]" if info else ""), flush=True)


def w(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def make(name):
    w(f"{T}/eng.srt", "1\n00:00:01,000 --> 00:00:04,000\nHello\n")
    w(f"{T}/rus.srt", "1\n00:00:01,000 --> 00:00:04,000\nПривет\n")
    w(f"{T}/ch.txt", ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=30000\ntitle=One\n"
                     "[CHAPTER]\nTIMEBASE=1/1000\nSTART=30000\nEND=60000\ntitle=Two\n")
    w(f"{T}/font.ttf", "not really a font")
    out = f"{T}/{name}"
    cmd = ["ffmpeg", "-v", "error", "-y",
           "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=60",
           "-f", "lavfi", "-i", "sine=f=440:duration=60",
           "-f", "lavfi", "-i", "sine=f=660:duration=60",
           "-f", "lavfi", "-i", "sine=f=880:duration=60",
           "-i", f"{T}/eng.srt", "-i", f"{T}/rus.srt", "-f", "ffmetadata", "-i", f"{T}/ch.txt",
           "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:a", "-map", "4:s", "-map", "5:s",
           "-map_chapters", "6",
           "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "ac3", "-b:a", "192k", "-c:s", "srt",
           "-metadata:s:a:0", "title=MVO Гаврилов", "-metadata:s:a:0", "language=und",
           "-metadata:s:a:1", "title=English 5.1", "-metadata:s:a:1", "language=eng",
           "-metadata:s:a:2", "title=Commentary", "-metadata:s:a:2", "language=eng",
           "-metadata:s:s:0", "language=eng", "-metadata:s:s:1", "language=rus",
           "-disposition:a:0", "default", "-disposition:a:1", "0", "-disposition:a:2", "0",
           "-attach", f"{T}/font.ttf", "-metadata:s:t", "mimetype=application/x-truetype-font",
           out]
    subprocess.run(cmd, check=True)
    return out


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while b := f.read(1 << 20):
            h.update(b)
    return h.hexdigest()


def raw(p):
    return json.loads(subprocess.run(["ffprobe", "-v", "quiet", "-print_format", "json",
                                      "-show_streams", "-show_chapters", p],
                                     capture_output=True, text=True).stdout)


async def new_job(path, status="queued"):
    async with SessionLocal() as s:
        j = StripJob(media_file_id=-1, path=path, status=status)
        s.add(j)
        await s.commit()
        IDS.append(j.id)
        return j.id


async def get(jid):
    async with SessionLocal() as s:
        return await s.get(StripJob, jid)


async def request(jid, req):
    async with SessionLocal() as s:
        (await s.get(StripJob, jid)).request = req
        await s.commit()
    await strip.handle_requests()


IDS = []


async def main():
    try:
        # 1. Strip.
        src = make("a.mkv")
        orig_hash = sha(src)
        jid = await new_job(src)
        await strip.run_job(jid)
        j = await get(jid)
        check("strip finishes", j.status == "done", f"{j.status} {j.error}")
        check("original kept as .pre-strip, byte-identical",
              os.path.exists(src + ".pre-strip") and sha(src + ".pre-strip") == orig_hash)
        after = await probe_file(src)
        a = [x for x in after["streams"] if x["kind"] == "audio"]
        check("audio: English first, commentary last, dub gone",
              [x["title"] for x in a] == ["English 5.1", "Commentary"], [x["title"] for x in a])
        check("only the first audio is default", a[0]["is_default"] and not a[1]["is_default"])
        subs = [x["language"] for x in after["streams"] if x["kind"] == "subtitle"]
        check("only English subtitles kept", subs == ["eng"], subs)
        r = raw(src)
        check("font attachment kept", any(s["codec_type"] == "attachment" for s in r["streams"]))
        check("chapters kept", len(r.get("chapters", [])) == 2, len(r.get("chapters", [])))
        check("duration unchanged", abs(after["duration"] - 60) < 1, after["duration"])
        check("SSD staging cleaned up", os.listdir(STAGE) == [], os.listdir(STAGE))
        check("no .stripping left behind", not os.path.exists(src + ".stripping"))
        check("sizes recorded", j.original_bytes and j.new_bytes and j.new_bytes < j.original_bytes,
              f"{j.original_bytes} -> {j.new_bytes}")

        # 2. Undo.
        await request(jid, "undo")
        j = await get(jid)
        check("undo puts the original back", j.status == "undone" and sha(src) == orig_hash
              and not os.path.exists(src + ".pre-strip"), j.status)

        # 3. Strip again, then confirm.
        jid2 = await new_job(src)
        await strip.run_job(jid2)
        check("second strip finishes", (await get(jid2)).status == "done")
        await request(jid2, "confirm")
        j = await get(jid2)
        check("confirm deletes only the kept original", j.status == "confirmed"
              and not os.path.exists(src + ".pre-strip") and os.path.exists(src), j.status)
        check("deletion logged", os.path.exists(f"{T}/data/strip_deletions.log"))

        # 4. Already clean.
        jid3 = await new_job(src)
        await strip.run_job(jid3)
        j = await get(jid3)
        check("clean file skipped, untouched", j.status == "skipped", f"{j.status} {j.error}")

        # 5. Damaged file: fails, original byte-identical.
        bad = make("b.mkv")
        os.truncate(bad, os.path.getsize(bad) // 2)
        bad_hash = sha(bad)
        jid4 = await new_job(bad)
        await strip.run_job(jid4)
        j = await get(jid4)
        check("damaged file fails safely", j.status == "failed" and sha(bad) == bad_hash
              and not os.path.exists(bad + ".pre-strip") and os.listdir(STAGE) == [],
              f"{j.status}: {j.error}")

        # 6. Crash mid-swap: original renamed, partial new file present.
        c = make("c.mkv")
        c_hash = sha(c)
        os.rename(c, c + ".pre-strip")
        w(c + ".stripping", "partial")
        jid5 = await new_job(c, status="running")
        await strip.recover()
        j = await get(jid5)
        check("crash recovery restores the original", os.path.exists(c) and sha(c) == c_hash
              and not os.path.exists(c + ".pre-strip") and not os.path.exists(c + ".stripping"))
        check("crash recovery fails the job", j.status == "failed", j.error)

        # 7. Fan preservation by name.
        p = make("Star Wars Harmy Despecialized.mkv")
        p_hash = sha(p)
        jid6 = await new_job(p)
        await strip.run_job(jid6)
        j = await get(jid6)
        check("protected name skipped, untouched", j.status == "skipped" and sha(p) == p_hash, j.error)
    finally:
        async with SessionLocal() as s:
            await s.execute(delete(StripJob).where(StripJob.id.in_(IDS)))
            await s.commit()
    print(f"\n{sum(results)}/{len(results)} passed", flush=True)


asyncio.run(main())
