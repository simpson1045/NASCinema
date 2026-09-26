import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native hero trailer: media_kit/libmpv rendering into a Flutter texture.
/// Trailers are SDR VP9 — the in-texture path the 4K HDR DV feature files
/// can't use is fine here, and a texture composites/scrolls with the list
/// (an mpv `--wid` child window could not).
///
/// ONE player for the hero's whole life. The first version created a new
/// Player per trailer and disposed the old one; flipping through the hero
/// raced a native teardown against the next start and libmpv aborted the
/// process (0xc0000409 in ucrtbase, twice on ELKO). Now switching trailers
/// just opens new media in the same player, and every open/stop runs
/// strictly in order.
///
/// The hero only dissolves from backdrop to video once playback is actually
/// advancing — if the texture path fails on some machine, `playing` alone
/// would swap to a black box with no way to detect it.
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
  int _generation = 0; // bumps on every open/stop; stale events are ignored
  int _shownFor = -1; // generation whose first frame was already reported
  bool _active = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  static bool _mkInit = false;

  bool get supported => true;

  /// Where the current trailer is, in seconds (for flags + the progress bar).
  double get positionSeconds =>
      (_player?.state.position.inMilliseconds ?? 0) / 1000;

  double get durationSeconds =>
      (_player?.state.duration.inMilliseconds ?? 0) / 1000;

  bool get paused => !(_player?.state.playing ?? false);

  Future<void> togglePause() => _run(() async => _player?.playOrPause());

  /// Relative seek, clamped to the trailer.
  Future<void> seekBy(double seconds) => _run(() async {
        final p = _player;
        if (p == null) return;
        final d = p.state.duration;
        var to = p.state.position + Duration(milliseconds: (seconds * 1000).round());
        if (to < Duration.zero) to = Duration.zero;
        if (d > Duration.zero && to > d) to = d;
        await p.seek(to);
      });

  /// Serialize every player operation — no two ever overlap.
  Future<void> _run(Future<void> Function() op) =>
      _queue = _queue.then((_) => _disposed ? null : op()).catchError((_) {});

  Player _ensurePlayer() {
    if (_player != null) return _player!;
    if (!_mkInit) {
      MediaKit.ensureInitialized();
      _mkInit = true;
    }
    final player = Player();
    _player = player;
    // Software decoding: every trailer showed a dotted patch in the middle
    // every few frames on ELKO (RTX 3070) while the files decode clean on the
    // NAS — hardware VP9 decode is the suspect. Trailers are small; the CPU
    // handles 4K VP9 easily. (Movies use the separate mpv renderer.)
    _controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(hwdec: 'no'),
    );
    _subs.add(player.stream.completed.listen((done) {
      if (done && _active) {
        _active = false;
        onFinished();
      }
    }));
    _subs.add(player.stream.error.listen((_) {
      if (_active) {
        _active = false;
        onError();
      }
    }));
    // Real frames are flowing once the position moves past zero.
    _subs.add(player.stream.position.listen((pos) {
      if (_active && _shownFor != _generation && pos > Duration.zero) {
        _shownFor = _generation;
        onFirstFrame();
      }
    }));
    return player;
  }

  Future<void> open(String url, {required bool muted}) {
    final gen = ++_generation;
    _active = false;
    return _run(() async {
      if (gen != _generation) return; // superseded before it ran
      final player = _ensurePlayer();
      await player.setVolume(muted ? 0 : 100);
      if (gen != _generation) return;
      _active = true;
      await player.open(Media(url));
    });
  }

  Future<void> setMuted(bool muted) =>
      _run(() async => _player?.setVolume(muted ? 0 : 100));

  Future<void> stop() {
    _generation++;
    _active = false;
    return _run(() async => _player?.stop());
  }

  /// [fit] cover fills the box (the mouse hero); contain never crops (big
  /// picture, whose trailers must keep every pixel — titles, on-screen text).
  Widget? view({BoxFit fit = BoxFit.cover}) {
    final c = _controller;
    if (c == null) return null;
    return Video(
      controller: c,
      controls: NoVideoControls,
      fit: fit,
      fill: const Color(0x00000000),
    );
  }

  /// The only place the native player is torn down — when its owner is gone.
  void dispose() {
    _generation++;
    _active = false;
    final player = _player;
    _queue = _queue.then((_) async {
      for (final s in _subs) {
        await s.cancel();
      }
      _subs.clear();
      await player?.dispose();
    }).catchError((_) {});
    _disposed = true;
    _player = null;
    _controller = null;
  }
}
