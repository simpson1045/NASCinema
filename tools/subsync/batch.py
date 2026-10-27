"""Speech-matched subtitles for a run of episodes (runs on ALPINE: Whisper on the 3080).

Per episode, in order, skipping any already in OUT:
  1. OpenSubtitles: English sub for the show's TMDB id + TMDB season/episode
     (non-SDH, most downloaded) — fetched here, never stored on the server raw;
  2. audio: ffmpeg straight from NASCinema's stream URL (16 kHz mono wav);
  3. Whisper (model loaded once) -> word timestamps;
  4. align.py (re-time every line to its spoken words) + fill_gaps.py (drop
     lines nobody says, fill uncovered speech from the transcript).
A sub that matches under 60% of its lines is the wrong cut/episode -> the
transcript alone is used. Writes OUT/<file_id>.vtt + OUT/batch.log.

env: OS_API_KEY. Usage:
  batch.py <base_url> <show_id> <folder_season> <tmdb_id> <tmdb_season> <first_ep> <last_ep> <out_dir>
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import whisper

base, show_id, season, tmdb_id, tmdb_season, first, last, out = sys.argv[1:9]
season, first, last = int(season), int(first), int(last)
HERE = os.path.dirname(os.path.abspath(__file__))
OS_BASE = "https://api.opensubtitles.com/api/v1"
HDRS = {"Api-Key": os.environ["OS_API_KEY"], "User-Agent": "NASCinema v0.9.0",
        "Content-Type": "application/json", "Accept": "application/json"}
os.makedirs(out, exist_ok=True)
logf = open(os.path.join(out, "batch.log"), "a", encoding="utf-8")


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    logf.write(line + "\n")
    logf.flush()


def get_json(url, data=None, headers=None):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data else None,
                                 headers=headers or {}, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


NOISE = re.compile(r"^(mythbusters|myth|busters|s\d+e\d+|\d+x\d+|\d{3,4}p|hevc|x26[45]|h26[45]|xvid|"
                   r"dvdrip|webrip|web|dl|hdtv|bluray|aac|ac3|eac3)$")


def title_words(text):
    return {w for w in re.findall(r"[a-z0-9]+", (text or "").lower()) if not NOISE.match(w)}


def os_candidates(title, ep):
    """Subtitles for this episode, best first: [(file_id, release)].
    OpenSubtitles numbers MythBusters differently from TMDB/Sonarr ("7x3" there is
    Exploding Bumper; ours is Banana Slip/Double Dip) and files some subs under the
    wrong episode — the RELEASE name is the reliable part. So: search by our title
    (and by number for extra candidates), keep results whose release name or
    episode title contains our title's words, numbers included ("Alaska Special
    (1)" is not "(2)")."""
    ours = title_words(title)
    nums = {w for w in ours if w.isdigit()}
    found = {}
    for params in ({"languages": "en", "parent_tmdb_id": tmdb_id, "query": " ".join(sorted(ours))},
                   {"episode_number": ep, "languages": "en", "parent_tmdb_id": tmdb_id,
                    "season_number": tmdb_season}):
        q = urllib.parse.urlencode(sorted(params.items()))
        for it in get_json(f"{OS_BASE}/subtitles?{q}", headers=HDRS).get("data", []):
            a = it["attributes"]
            names = [a.get("release") or "", (a.get("feature_details") or {}).get("title") or ""]
            rel, feat = (len(ours & title_words(n)) / max(len(ours), 1) for n in names)
            # A release name with real title words has to match ("...S07E04 - Banana
            # Slip, Double Dip" filed under "YouTube Special" cost two downloads);
            # the episode title only counts when the release name says nothing.
            score = rel if title_words(names[0]) else feat
            if score < 0.75 or not nums <= title_words(names[0] if title_words(names[0]) else names[1]):
                continue
            for f in a.get("files", []):
                # the release name outranks the episode title (mislabeled entries)
                found[f["file_id"]] = (-rel, -feat, a.get("hearing_impaired", False),
                                       -a.get("download_count", 0), f["file_id"], a.get("release") or "")
    return [(c[4], c[5]) for c in sorted(found.values())]


def os_sub(fid, release):
    """(srt text, release) for one OpenSubtitles file id."""
    d = get_json(f"{OS_BASE}/download", data={"file_id": fid}, headers=HDRS)
    log(f"  sub {fid} '{release}' (downloads left today: {d.get('remaining')})")
    # The download CDN answers 403 to Python's default User-Agent.
    raw = urllib.request.urlopen(urllib.request.Request(d["link"], headers={"User-Agent": HDRS["User-Agent"]}),
                                 timeout=60).read()
    for enc in ("utf-8-sig", "cp1252"):  # cp1252: "CLICHÉS" came out "CLICH?S" otherwise
        try:
            return raw.decode(enc), release
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace"), release


def srt_to_vtt(srt):
    srt = srt.replace("\r", "")
    srt = re.sub(r"^\d+\n(?=\d\d:\d\d:\d\d,\d{3} -->)", "", srt, flags=re.M)
    return "WEBVTT\n\n" + re.sub(r"(\d\d:\d\d:\d\d),(\d{3})", r"\1.\2", srt).strip() + "\n"


def run(*args):
    r = subprocess.run([sys.executable, *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise RuntimeError(r.stderr[-500:])
    return r.stdout


show = get_json(f"{base}/api/shows/{show_id}")
eps = sorted((e for e in show["episodes"] if e["season_number"] == season
              and e["episode_number"] is not None and first <= e["episode_number"] <= last
              and e.get("files")), key=lambda e: e["episode_number"])
log(f"== {show['title']} season {season}: {len(eps)} episodes (E{first}-E{last}) -> {out}")
model = whisper.load_model("turbo", device="cuda")

for e in eps:
    fid, n = e["files"][0]["id"], e["episode_number"]
    dest = os.path.join(out, f"{fid}.vtt")
    if os.path.exists(dest):
        log(f"E{n} ({fid}) already done")
        continue
    t0 = time.time()
    log(f"E{n} ({fid}) {e['title']}")
    work = os.path.join(out, f"work-{fid}")
    os.makedirs(work, exist_ok=True)
    wav, words_p = os.path.join(work, "audio.wav"), os.path.join(work, "words.json")
    if os.path.exists(words_p):  # transcribed on an earlier run
        words = json.load(open(words_p, encoding="utf-8"))
        log(f"  {len(words)} words from the earlier transcript")
    else:
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", f"{base}/api/stream/{fid}/direct",
                        "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav],
                       check=True)
        res = model.transcribe(wav, language="en", word_timestamps=True,
                               condition_on_previous_text=False, verbose=None)
        words = [{"start": w["start"], "end": w["end"], "word": w["word"]}
                 for seg in res["segments"] for w in seg.get("words", [])]
        json.dump(words, open(words_p, "w", encoding="utf-8"))
        os.remove(wav)  # 50-180 MB each; words.json + base/matched stay for re-runs
        log(f"  audio + {len(words)} words in {time.time() - t0:.0f} s")

    empty = os.path.join(work, "empty.vtt")
    open(empty, "w", encoding="utf-8").write("WEBVTT\n")
    base_vtt = empty
    try:
        cands = os_candidates(e["title"], n)
    except Exception as ex:  # quota / network: still give the episode a transcript
        log(f"  OpenSubtitles search failed ({ex})")
        cands = []
    if not cands:
        log("  no subtitle with this episode's title -> transcript only")
    for k, (os_id, release) in enumerate(cands[:2]):  # 2 tries: downloads are rationed
        try:
            got = os_sub(os_id, release)
        except Exception as ex:
            log(f"  download {os_id} failed ({ex})")
            continue
        sub_vtt = os.path.join(work, f"base{k}.vtt")  # not `base` — that's the server URL
        open(sub_vtt, "w", encoding="utf-8").write(srt_to_vtt(got[0]))
        matched = os.path.join(work, f"matched{k}.vtt")
        report = run(os.path.join(HERE, "align.py"), words_p, sub_vtt, matched)
        m = re.search(r"matched \d+ \((\d+)%\)", report)
        pct = int(m.group(1)) if m else 0
        log(f"  aligned: {pct}% of lines matched")
        if pct >= 60:
            base_vtt = matched
            break
        log("  under 60% -> wrong cut/episode")
    if base_vtt == empty and cands:
        log("  no subtitle lined up -> transcript only")
    report = run(os.path.join(HERE, "fill_gaps.py"), words_p, base_vtt, dest)
    log(f"  {report.strip()} | {time.time() - t0:.0f} s total")

log("== batch done")
