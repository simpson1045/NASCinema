import 'dart:typed_data';

class ReelOverlay {
  ReelOverlay(this.rgba, this.width, this.height);
  final ByteData rgba;
  final int width;
  final int height;
}

/// Web: no native reel — the hero keeps its texture/backdrop behavior.
class HeroReel {
  HeroReel({required void Function() onFinished});

  bool get supported => false;
  bool get showing => false;
  double get positionSeconds => 0;

  Future<bool> play(String url,
          {double start = 0,
          Future<void> Function()? beforeShow,
          Future<ReelOverlay?> Function()? overlay}) async =>
      false;
  Future<bool> handoff(String url,
          {required double Function() sourcePos,
          required Future<ReelOverlay?> Function() overlay}) async =>
      false;
  Future<void> fadeOut() async {}
  Future<void> warm(String url) async {}
  Future<void> hide() async {}
  Future<void> dispose() async {}
}
