"""Transcribe a wav with word timestamps -> JSON [{start, end, word}, ...]."""
import json
import sys
import time

import whisper

wav, out = sys.argv[1], sys.argv[2]
t0 = time.time()
model = whisper.load_model("turbo", device="cuda")
res = model.transcribe(wav, language="en", word_timestamps=True, condition_on_previous_text=False,
                       verbose=False)
words = [{"start": w["start"], "end": w["end"], "word": w["word"]}
         for seg in res["segments"] for w in seg.get("words", [])]
json.dump(words, open(out, "w", encoding="utf-8"))
print(f"{len(words)} words in {time.time() - t0:.0f} s; last at {words[-1]['end']:.0f} s")
