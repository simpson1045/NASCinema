import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native hero trailer: media_kit/libmpv rendering into a Flutter texture.
/// Trailers are SDR VP9 — the in-texture path the 4K HDR DV feature files
/// can't use is fine here, and a texture composites/scrolls with the list
/// (an mpv `--wid` child window could not).
///
/// The hero only dissolves from backdrop to video after the FIRST FRAME
/// actually renders — if the texture path fails on some machine, `playing`
/// alone would swap to a black box with no way to detect it.
class TrailerPlayer {
  TrailerPlayer({
    required this.onFirstFrame,
    required this.onFinished,
    required this.onError,
  });

  final VoidCallback onFirstFrame;
  final VoidCallback onFinished;
  final VoidCallback onError;

  Player? _player;
  VideoController? _controller;
  final _subs = <StreamSubscription>[];
  int _generation = 0;
  static bool _mkInit = false;

  bool get supported => true;

  Future<void> open(String url, {required bool muted}) async {
    if (!_mkInit) {
      MediaKit.ensureInitialized();
      _mkInit = true;
    }
    await stop();
    final gen = ++_generation;
    final player = Player();
    final controller = VideoController(player);
    _player = player;
    _controller = controller;

    _subs.add(player.stream.completed.listen((done) {
      if (done && gen == _generation) onFinished();
    }));
    _subs.add(player.stream.error.listen((_) {
      if (gen == _generation) onError();
    }));

    await player.setVolume(muted ? 0 : 100);
    await player.open(Media(url));
    unawaited(controller.waitUntilFirstFrameRendered.then((_) {
      if (gen == _generation) onFirstFrame();
    }));
  }

  Future<void> setMuted(bool muted) async =>
      _player?.setVolume(muted ? 0 : 100);

  Future<void> stop() async {
    _generation++;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final p = _player;
    _player = null;
    _controller = null;
    await p?.dispose();
  }

  Widget? view() {
    final c = _controller;
    if (c == null) return null;
    return Video(
      controller: c,
      controls: NoVideoControls,
      fit: BoxFit.cover,
      fill: const Color(0x00000000),
    );
  }

  void dispose() {
    unawaited(stop());
  }
}
