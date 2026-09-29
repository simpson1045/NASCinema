import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher, Rect;

import '../services/mpv/embed_window.dart';
import '../services/mpv/mpv_controller.dart';

/// The fullscreen hero reel on Windows: trailers in native mpv (embedded,
/// full window) instead of the media_kit texture. The texture path is Flutter
/// compositing every video frame, and 24p through it stutters; mpv in a
/// window Flutter never repaints dropped 0 frames on ELKO (2026-09-28).
///
/// Nothing Flutter draws may sit above native video, so the hero's scrim +
/// logo + rating row are rendered to a bitmap once per trailer and shown by
/// mpv itself ([setOverlay], `overlay-add`). While a trailer plays, Flutter
/// draws nothing new.
///
/// ONE mpv for the reel's life, reused with loadfile; every operation runs in
/// order. The window stays hidden until frames are actually flowing, so a
/// slow start shows the Flutter backdrop, never a black box.
class HeroReel {
  HeroReel({required this.onFinished});

  final void Function() onFinished;

  EmbedWindow? _win;
  MpvController? _mpv;
  Timer? _watch;
  bool _showing = false;
  int _gen = 0; // bumps on every play/hide; stale work bails out
  Future<void> _queue = Future.value();
  static const _overlayId = 3;
  int _overlaySlot = 0; // alternate files: mpv maps the one on screen

  bool get supported => Platform.isWindows;
  bool get showing => _showing;
  double get positionSeconds => _mpv?.position ?? 0;

  Future<T> _run<T>(Future<T> Function() op) {
    final f = _queue.then((_) => op());
    _queue = f.then((_) {}, onError: (_) {});
    return f;
  }

  /// The whole Flutter view, in physical pixels (= the root client area).
  Rect _screenRect() {
    final v = PlatformDispatcher.instance.views.first;
    return Rect.fromLTWH(0, 0, v.physicalSize.width, v.physicalSize.height);
  }

  /// Play [url] from [start]; resolves true once frames are on screen.
  Future<bool> play(String url, {double start = 0}) {
    final gen = ++_gen;
    return _run(() async {
      if (gen != _gen) return false;
      _watch?.cancel();
      final rect = _screenRect();
      final win = _win ??= EmbedWindow.create(rect);
      if (win == null) return false;
      win.setVisible(false);
      win.setBounds(rect);
      var c = _mpv;
      if (c == null || !c.running) {
        // (A movie launch disposes our mpv — MpvController keeps one live —
        // so "not running" just means start a fresh one.)
        c = await MpvController.launch(
            media: url, hwnd: win.hwnd, startSeconds: start);
        if (c == null) return false;
        _mpv = c;
        win.focusApp(); // mpv's window grabs focus as it spawns
      } else {
        c.overlayRemove(_overlayId);
        c.loadFile(url, start: start);
      }
      c.setMute(false);
      c.setPaused(false);
      // Frames are flowing once the position moves past the start and the
      // previous file's EOF flag has cleared.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (gen != _gen || !c.running) return false;
        if (!c.eofReached && c.position > start + 0.05) break;
      }
      if (gen != _gen || c.position <= start + 0.05) return false;
      win.fitInner();
      win.setVisible(true);
      _showing = true;
      var fired = false;
      _watch = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (gen != _gen || fired) return;
        if (!c!.running) {
          _watch?.cancel();
          win.setVisible(false);
          _showing = false;
        } else if (c.eofReached) {
          fired = true;
          onFinished();
        }
      });
      return true;
    });
  }

  /// Show [rgba] (premultiplied RGBA, [w]x[h] physical pixels — the whole
  /// window) above the video. Converted to mpv's BGRA off the UI isolate.
  Future<void> setOverlay(ByteData rgba, int w, int h) {
    final gen = _gen;
    return _run(() async {
      final c = _mpv;
      if (gen != _gen || c == null || !c.running) return;
      _overlaySlot ^= 1;
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}nascinema_reel_$_overlaySlot.bgra';
      final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      await Isolate.run(() {
        final out = Uint8List.fromList(bytes);
        for (var i = 0; i < out.length; i += 4) {
          final r = out[i];
          out[i] = out[i + 2];
          out[i + 2] = r;
        }
        File(path).writeAsBytesSync(out, flush: true);
      });
      if (gen != _gen || !c.running) return;
      c.overlayImage(_overlayId, path, w, h);
    });
  }

  /// Take the video off screen (Flutter's backdrop shows again) and pause.
  /// The mpv process stays up for the next trailer.
  Future<void> hide() {
    ++_gen;
    _watch?.cancel();
    _showing = false;
    _win?.setVisible(false);
    return _run(() async {
      final c = _mpv;
      if (c != null && c.running) {
        c.overlayRemove(_overlayId);
        c.setPaused(true);
      }
    });
  }

  Future<void> dispose() async {
    await hide();
    await _run(() async {
      await _mpv?.dispose();
      _mpv = null;
      _win?.destroy();
      _win = null;
    });
  }
}
