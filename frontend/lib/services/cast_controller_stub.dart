import 'package:flutter/foundation.dart';

import 'cast/cast_device.dart';

/// Web fallback: the pure-Dart cast stack needs raw TLS sockets (dart:io),
/// which the browser can't do. No-op here so the rest of the app compiles on
/// web; casting from the browser would need the HTTPS-gated CAF sender instead.
class CastController extends ChangeNotifier {
  bool get supported => false;
  List<CastDevice> get devices => const [];
  bool get isDiscovering => false;
  bool get isConnected => false;
  CastDevice? get connectedDevice => null;
  String get playerState => 'IDLE';
  int? get castingFileId => null;
  String get castingTitle => '';
  Duration get position => Duration.zero;
  Duration get duration => Duration.zero;
  bool get isPlaying => false;
  double get volume => 1.0;
  bool get muted => false;
  bool get volumeControllable => false;
  bool get hasSubtitles => false;
  bool get subtitlesOn => false;

  Future<void> discover({Duration timeout = const Duration(seconds: 8)}) async {}
  Future<bool> connect(CastDevice device) async => false;
  Future<void> castVideo({
    required int fileId,
    required String url,
    required String contentType,
    required String title,
    String? subUrl,
  }) async {}
  void play() {}
  void pause() {}
  void stop() {}
  void seekTo(double seconds) {}
  void toggleSubtitles() {}
  void setVolume(double v) {}
  void adjustVolume(double delta) {}
  Future<void> disconnect() async {}
}
