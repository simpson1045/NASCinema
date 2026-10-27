"""Fill the holes in a matched subtitle with the Whisper transcript.

A re-edited copy (FilmRise MythBusters) has narration and footage the broadcast
never had, so no downloaded subtitle covers it (~10% of the words in S2009E1).
Every stretch of speech with no cue on screen becomes new cues from the
transcript: ALL CAPS like broadcast captions, two lines of ~42 characters at
most, broken at pauses and sentence ends, never overlapping a real cue.
Usage: fill_gaps.py words.json matched.vtt out.vtt
"""
import bisect
import json
import re
import sys

words_path, vtt_in, vtt_out = sys.argv[1:4]
TS = r"(\d+):(\d\d):(\d\d)\.(\d{3})"
LINE, MAX_CHARS, MAX_SECS, PAUSE = 42, 84, 6.0, 0.7
# Names Whisper hears wrong (MythBusters cast); whole words, case-insensitive.
FIXES = {"cary": "KARI", "carrie": "KARI", "kerry": "KARI", "tori": "TORY", "torrey": "TORY",
         "jamie hyneman": "JAMIE HYNEMAN", "myth busters": "MYTHBUSTERS"}


def secs(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def stamp(t):
    h, rem = divmod(max(t, 0), 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}"


def fix(text):
    text = re.sub(r" -(?=\w)", "-", text.upper())  # Whisper writes "MIND -BLOWING"
    for wrong, right in FIXES.items():
        text = re.sub(rf"\b{wrong.upper()}\b", right, text)
    return text


def wrap(text):
    if len(text) <= LINE:
        return text
    cut = text.rfind(" ", 0, len(text) // 2 + 8)
    return text[:cut] + "\n" + text[cut + 1:] if cut > 0 else text


cues = []
for block in re.split(r"\n\s*\n", open(vtt_in, encoding="utf-8").read().replace("\r", "")):
    m = re.search(TS + r"\s*-->\s*" + TS, block)
    if m:
        cues.append((secs(*m.groups()[:4]), secs(*m.groups()[4:]), block[m.end():].strip(), False))
starts = [c[0] for c in cues]


def covered(t):
    i = bisect.bisect_right(starts, t) - 1
    return i >= 0 and cues[i][0] - 0.3 <= t <= cues[i][1] + 0.3


words = [w for w in json.load(open(words_path, encoding="utf-8")) if w["word"].strip()]
stretches, cur = [], []
for w in words:
    if covered(w["start"]):
        if cur:
            stretches.append(cur)
        cur = []
    elif cur and w["start"] - cur[-1]["end"] > 1.5:
        stretches.append(cur)
        cur = [w]
    else:
        cur.append(w)
if cur:
    stretches.append(cur)

added = []
for run in (r for r in stretches if len(r) >= 3):  # stray "yeah"/"okay" stay unsubtitled
    group = []
    for w in run + [None]:
        if group and (w is None
                      or w["start"] - group[-1]["end"] > PAUSE
                      or w["end"] - group[0]["start"] > MAX_SECS
                      or len(" ".join(x["word"].strip() for x in group + [w])) > MAX_CHARS
                      or group[-1]["word"].strip().endswith((".", "?", "!"))):
            text = fix(" ".join(x["word"].strip() for x in group))
            added.append((group[0]["start"], max(group[-1]["end"] + 0.3, group[0]["start"] + 1.0),
                          wrap(text), True))
            group = []
        if w is not None:
            group.append(w)

merged = sorted(cues + added, key=lambda c: c[0])
out, filled = ["WEBVTT", ""], 0
for n, (s, e, text, new) in enumerate(merged):
    nxt = merged[n + 1][0] if n + 1 < len(merged) else e
    if new:
        e = min(e, nxt - 0.02)
        if e - s < 0.4:  # no room between real cues
            continue
        filled += 1
    out += [f"{stamp(s)} --> {stamp(e)}", text, ""]
open(vtt_out, "w", encoding="utf-8").write("\n".join(out))
print(f"real cues {len(cues)}, transcript cues added {filled} "
      f"(from {sum(1 for r in stretches if len(r) >= 3)} uncovered stretches)")
