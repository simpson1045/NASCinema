import 'dart:typed_data';

/// Web: no native reel — the hero keeps its texture/backdrop behavior.
class HeroReel {
  HeroReel({required void Function() onFinished});

  bool get supported => false;
  bool get showing => false;
  double get positionSeconds => 0;

  Future<bool> play(String url,
          {double start = 0, Future<void> Function()? beforeShow}) async =>
      false;
  Future<void> fadeOut() async {}
  Future<void> warm(String url) async {}
  Future<void> setOverlay(ByteData rgba, int w, int h) async {}
  Future<void> hide() async {}
  Future<void> dispose() async {}
}
