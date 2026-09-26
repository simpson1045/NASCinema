"""The strip command + verification (app/strip_cmd.py). No files or ffmpeg:
`python3 -m unittest discover tests` from backend/."""

import unittest

from app.strip_cmd import ffmpeg_args, verify
from app.track_rules import plan_file


def st(index, kind, lang=None, title="", default=False, forced=False, codec="ac3"):
    return {"index": index, "kind": kind, "language": lang, "title": title,
            "is_default": default, "is_forced": forced, "bit_rate": 640_000,
            "codec": codec, "channels": 6}


SRC = [st(0, "video", codec="hevc"),
       st(1, "audio", None, 'DVO / "Легендарный"', default=True),
       st(2, "audio", "eng", "Commentary", codec="aac"),
       st(3, "audio", "eng", "TrueHD Atmos", codec="truehd"),
       st(4, "subtitle", "eng", "Forced", forced=True, codec="subrip"),
       st(5, "subtitle", "rus", codec="subrip"),
       st(6, "subtitle", "eng", "SDH", default=True, codec="subrip")]
PLAN = plan_file("/movies/M/M.mkv", 7200.0, SRC)


def pairs(args, flag):
    return [args[i + 1] for i, a in enumerate(args) if a == flag]


class Command(unittest.TestCase):
    def test_maps_kept_tracks_in_plan_order(self):
        a = ffmpeg_args("ffmpeg", "in.mkv", "out.mkv", PLAN, "matroska")
        # video, then audio English-first/commentary-last, kept subs, attachments
        self.assertEqual(pairs(a, "-map"), ["0:0", "0:3", "0:2", "0:4", "0:6", "0:t?"])
        self.assertIn("-c", a)
        self.assertEqual(a[a.index("-c") + 1], "copy")
        self.assertEqual(a[-1], "out.mkv")
        self.assertEqual(a[a.index("-f") + 1], "matroska")

    def test_dispositions(self):
        a = ffmpeg_args("ffmpeg", "in.mkv", "out.mkv", PLAN, "matroska")
        disp = {a[i]: a[i + 1] for i, x in enumerate(a) if x.startswith("-disposition")}
        self.assertEqual(disp, {"-disposition:a:0": "default", "-disposition:a:1": "0",
                                "-disposition:s:0": "forced", "-disposition:s:1": "0"})

    def test_mp4_has_no_attachment_map(self):
        a = ffmpeg_args("ffmpeg", "in.mp4", "out.mp4", PLAN, "mp4")
        self.assertNotIn("0:t?", a)


def out_probe(**over):
    streams = [st(0, "video", codec="hevc"),
               st(1, "audio", "eng", "TrueHD Atmos", default=True, codec="truehd"),
               st(2, "audio", "eng", "Commentary", codec="aac"),
               st(3, "subtitle", "eng", "Forced", forced=True, codec="subrip"),
               st(4, "subtitle", "eng", "SDH", codec="subrip")]
    return {"duration": over.get("duration", 7195.0), "streams": over.get("streams", streams)}


class Verify(unittest.TestCase):
    def test_good_copy_passes(self):
        self.assertIsNone(verify(PLAN, out_probe(), 7200.0))

    def test_missing_track_fails(self):
        self.assertIn("track counts", verify(PLAN, out_probe(streams=out_probe()["streams"][:-1]), 7200.0))

    def test_short_file_fails(self):
        self.assertIn("duration", verify(PLAN, out_probe(duration=7000.0), 7200.0))

    def test_wrong_first_audio_fails(self):
        s = out_probe()["streams"]
        s[1], s[2] = s[2], s[1]
        self.assertIsNotNone(verify(PLAN, out_probe(streams=s), 7200.0))

    def test_second_default_fails(self):
        s = out_probe()["streams"]
        s[2] = {**s[2], "is_default": True}
        self.assertIn("default", verify(PLAN, out_probe(streams=s), 7200.0))

    def test_unreadable_fails(self):
        self.assertIsNotNone(verify(PLAN, None, 7200.0))


if __name__ == "__main__":
    unittest.main()
