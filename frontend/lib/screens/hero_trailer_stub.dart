import 'package:flutter/widgets.dart';

/// Web: no inline trailer playback — the hero shows backdrops only.
/// (A browser <video> leg could fill this in later; the hero degrades
/// gracefully to the exact pre-trailer behavior when [supported] is false.)
class TrailerPlayer {
  TrailerPlayer({
    required this.onFirstFrame,
    required this.onFinished,
    required this.onError,
  });

  VoidCallback onFirstFrame;
  VoidCallback onFinished;
  VoidCallback onError;

  bool get supported => false;

  double get positionSeconds => 0;
  double get durationSeconds => 0;
  bool get paused => false;
  Future<void> togglePause() async {}
  Future<void> seekBy(double seconds) async {}

  Future<void> open(String url, {required bool muted, double start = 0}) async {}

  Future<void> setMuted(bool muted) async {}

  Future<void> stop() async {}

  Widget? view({BoxFit fit = BoxFit.cover}) => null;

  void dispose() {}
}
