"""Track Manager rules (docs/SPEC-track-manager.md §3), incl. the real
incidents. No database or files: `python3 -m unittest discover tests` from
backend/."""

import unittest

from app.track_rules import keep_track, plan_file


def a(index, lang, title="", default=False, br=640_000, codec="ac3"):
    return {"index": index, "kind": "audio", "language": lang, "title": title,
            "is_default": default, "is_forced": False, "bit_rate": br,
            "codec": codec, "channels": 6}


def s(index, lang, title=""):
    return {"index": index, "kind": "subtitle", "language": lang, "title": title,
            "is_default": False, "is_forced": False, "bit_rate": 30_000,
            "codec": "subrip", "channels": None}


V = {"index": 0, "kind": "video", "language": None, "title": "", "is_default": True,
     "is_forced": False, "bit_rate": None, "codec": "hevc", "channels": None}
MOVIE = "/movies/Some Movie (2001)/Some Movie (2001).mkv"


class Rules(unittest.TestCase):
    def test_sorcerers_stone_untagged_russian_voiceover(self):
        # Audio #1: untagged Russian DVO, flagged default — played first on Roku.
        p = plan_file(MOVIE, 9000, [V, a(1, None, 'DVO, LDV / "Легендарный"', default=True),
                                    a(2, "eng", "TrueHD Atmos 7.1", codec="truehd")])
        self.assertEqual(p["status"], "strip")
        keep = {r["index"]: r["keep"] for r in p["streams"]}
        self.assertEqual(keep, {0: True, 1: False, 2: True})
        self.assertEqual(p["new_default_audio"], 2)
        self.assertTrue(p["foreign_default"])

    def test_dub_markers_on_untagged_tracks(self):
        for title in ("MVO", "AVO Gavrilov", "Volodarsky", "Dubbed", "Voice-over",
                      "rus", "UKR", "Дубляж"):
            self.assertFalse(keep_track(a(1, "und", title))[0], title)
        for title in ("", "Surround 5.1", "Original Mono", "Director's Commentary"):
            self.assertTrue(keep_track(a(1, "und", title))[0], title)

    def test_spelled_out_language_names_are_dubs(self):
        # Matt, 2026-09-26: "Russian" spelled out is as foreign as "rus".
        for title in ("Russian", "Ukrainian 5.1", "French", "Français", "Castellano",
                      "Latino", "Español", "German DTS", "Japanese"):
            self.assertFalse(keep_track(a(1, "und", title))[0], title)
        for title in ("English", "Stereo", "Original", "Director's Commentary"):
            self.assertTrue(keep_track(a(1, "und", title))[0], title)

    def test_foreign_tagged_tracks_drop(self):
        p = plan_file(MOVIE, 7200, [V, a(1, "eng", default=True), a(2, "rus"),
                                    a(3, "fre"), s(4, "eng"), s(5, "spa"),
                                    s(6, "und", "rus forced")])
        drop = sorted(r["index"] for r in p["streams"] if not r["keep"])
        self.assertEqual(drop, [2, 3, 5, 6])
        self.assertFalse(p["foreign_default"])
        # 2 × 640 kbps × 2 h + 2 × 30 kbps × 2 h
        self.assertEqual(p["savings_bytes"], 2 * 576_000_000 + 2 * 27_000_000)

    def test_english_first_commentary_last(self):
        p = plan_file(MOVIE, 7200, [V, a(1, "eng", "Commentary with the director"),
                                    a(2, "und", "Original Mono"), a(3, "eng", "DTS-HD MA 5.1"),
                                    a(4, "ger")])
        self.assertEqual(p["audio_order"], [3, 2, 1])
        self.assertEqual(p["new_default_audio"], 3)

    def test_fan_preservations_are_protected(self):
        for path in ("/movies/Star Wars (1977)/Star Wars Harmy Despecialized v2.7.mkv",
                     "/movies/Star Wars 4K77/Star Wars.mkv",
                     "/movies/Jurassic Park (1993) 35mm Open Matte/jp.mkv"):
            p = plan_file(path, 7200, [V, a(1, "eng"), a(2, "rus")])
            self.assertEqual(p["status"], "protected", path)
        self.assertEqual(plan_file(MOVIE, 7200, [V, a(1, "eng"), a(2, "rus")],
                                   manual_protect=True)["status"], "protected")

    def test_no_english_audio_is_skipped(self):
        p = plan_file(MOVIE, 7200, [V, a(1, "rus"), a(2, "ukr"), s(3, "eng")])
        self.assertEqual(p["status"], "no_english")

    def test_clean_file_is_never_rewritten(self):
        p = plan_file(MOVIE, 7200, [V, a(1, "eng"), s(2, "eng"), s(3, "und")])
        self.assertEqual(p["status"], "clean")
        self.assertEqual(p["drop_count"], 0)

    def test_missing_bitrate_marks_estimate_partial(self):
        p = plan_file(MOVIE, 7200, [V, a(1, "eng"), a(2, "rus", br=None)])
        self.assertTrue(p["savings_partial"])
        self.assertEqual(p["savings_bytes"], 0)


if __name__ == "__main__":
    unittest.main()
