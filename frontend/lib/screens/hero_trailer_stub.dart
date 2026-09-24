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

  final VoidCallback onFirstFrame;
  final VoidCallback onFinished;
  final VoidCallback onError;

  bool get supported => false;

  Future<void> open(String url, {required bool muted}) async {}

  Future<void> setMuted(bool muted) async {}

  Future<void> stop() async {}

  Widget? view({BoxFit fit = BoxFit.cover}) => null;

  void dispose() {}
}
