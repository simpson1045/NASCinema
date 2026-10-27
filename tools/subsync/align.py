"""Re-time a subtitle to a file using a Whisper word transcript of that file.

Every subtitle word is matched to the transcript (one global sequence alignment),
each cue gets the median shift of its matched words, outliers are smoothed with
a running median, and cues with no match inherit their neighbours' shift.
Usage: align.py words.json in.vtt out.vtt
"""
import difflib
import json
import re
import statistics
import sys

words_path, vtt_in, vtt_out = sys.argv[1:4]
TS = r"(\d+):(\d\d):(\d\d)\.(\d{3})"


def secs(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def stamp(t):
    t = max(t, 0)
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}"


def toks(text):
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)|<[^>]*>", " ", text)       # [explosion], <i>
    text = re.sub(r"^\s*[A-Za-z ]{1,20}:", " ", text, flags=re.M)     # "Narrator:"
    return re.findall(r"[a-z0-9']+", text.lower().replace("’", "'"))


words = json.load(open(words_path, encoding="utf-8"))
tw = [(w["start"], t) for w in words for t in toks(w["word"])]

raw = open(vtt_in, encoding="utf-8").read().replace("\r", "")
cues = []
for block in re.split(r"\n\s*\n", raw):
    m = re.search(TS + r"\s*-->\s*" + TS, block)
    if not m:
        continue
    text = block[m.end():].strip()
    cues.append({"start": secs(*m.groups()[:4]), "end": secs(*m.groups()[4:]), "text": text})

# subtitle tokens with an estimated time inside their cue
st, owner = [], []
for i, c in enumerate(cues):
    tk = toks(c["text"])
    for j, t in enumerate(tk):
        frac = j / max(len(tk), 1)
        st.append((c["start"] + frac * (c["end"] - c["start"]), t))
        owner.append(i)

sm = difflib.SequenceMatcher(None, [t for _, t in st], [t for _, t in tw], autojunk=False)
shifts = [[] for _ in cues]
for a, b, n in sm.get_matching_blocks():
    if n < 2:  # lone common words ("the") are noise
        continue
    for k in range(n):
        shifts[owner[a + k]].append(tw[b + k][0] - st[a + k][0])

per = [statistics.median(s) if s else None for s in shifts]
matched = sum(p is not None for p in per)

# fill gaps from the nearest matched neighbour, then a running median (window 9)
filled = per[:]
last = None
for i, p in enumerate(filled):
    if p is None:
        filled[i] = last
    else:
        last = p
nxt = None
for i in range(len(filled) - 1, -1, -1):
    if per[i] is not None:
        nxt = per[i]
    if filled[i] is None:
        filled[i] = nxt if nxt is not None else 0.0
smooth = [statistics.median(filled[max(0, i - 4): i + 5]) for i in range(len(filled))]

out = ["WEBVTT", ""]
for c, d in zip(cues, smooth):
    out += [f"{stamp(c['start'] + d)} --> {stamp(c['end'] + d)}", c["text"], ""]
open(vtt_out, "w", encoding="utf-8").write("\n".join(out))

print(f"cues {len(cues)}, matched {matched} ({100 * matched / len(cues):.0f}%), transcript words {len(tw)}")
prev = None
for c, d in zip(cues, smooth):
    if prev is None or abs(d - prev) > 1.0:
        print(f"  from sub {stamp(c['start'])} (file {stamp(c['start'] + d)}): shift {d:+.1f} s")
        prev = d
