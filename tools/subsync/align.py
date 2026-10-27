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

# Each cue keeps its OWN measured shift. A running median over every cue (the
# first version) dragged cues across the cut points — at a jump the last cues of
# one section took the next section's shift and showed before the lines ahead of
# them ("bleeding through", MythBusters 42:01, 2026-10-26). Now: a matched cue is
# only overridden when it's a lone outlier (both matched neighbours agree with
# each other and not with it); an unmatched cue borrows from its nearest matched
# neighbour in time.
idx = [i for i, p in enumerate(per) if p is not None]
smooth = per[:]
for k, i in enumerate(idx):
    if 0 < k < len(idx) - 1:
        a, b = per[idx[k - 1]], per[idx[k + 1]]
        if abs(a - b) < 2 and abs(per[i] - a) > 5:
            smooth[i] = (a + b) / 2
for i, p in enumerate(per):
    if p is None:
        before = max((j for j in idx if j < i), default=None)
        after = min((j for j in idx if j > i), default=None)
        if before is None and after is None:
            smooth[i] = 0.0
        elif after is None or (before is not None and
                               cues[i]["start"] - cues[before]["end"] <= cues[after]["start"] - cues[i]["end"]):
            smooth[i] = smooth[before]
        else:
            smooth[i] = smooth[after]

# Never start before the line ahead, never overlap the next one: mpv stacks
# overlapping cues on screen.
timed = sorted(((c["start"] + d, c["end"] + d, c["text"]) for c, d in zip(cues, smooth)),
               key=lambda t: t[0])
fixed = []
for n, (s, e, text) in enumerate(timed):
    nxt = timed[n + 1][0] if n + 1 < len(timed) else e
    fixed.append((s, max(min(e, nxt - 0.02), s + 0.3), text))

out = ["WEBVTT", ""]
for s, e, text in fixed:
    out += [f"{stamp(s)} --> {stamp(e)}", text, ""]
open(vtt_out, "w", encoding="utf-8").write("\n".join(out))
overlaps = sum(1 for x, y in zip(fixed, fixed[1:]) if y[0] < x[1] - 0.01)
print(f"overlapping cues after the fix: {overlaps}")

print(f"cues {len(cues)}, matched {matched} ({100 * matched / len(cues):.0f}%), transcript words {len(tw)}")
prev = None
for c, d in zip(cues, smooth):
    if prev is None or abs(d - prev) > 1.0:
        print(f"  from sub {stamp(c['start'])} (file {stamp(c['start'] + d)}): shift {d:+.1f} s")
        prev = d
