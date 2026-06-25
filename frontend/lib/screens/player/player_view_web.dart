import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('nascinemaAttachHls')
external void _attachHls(web.HTMLVideoElement video, String url);

int _counter = 0;
web.HTMLVideoElement? _v;

/// Web player: an HTML <video> with NATIVE controls off — our Flutter control
/// bar drives it through the accessors below. Playback starts via play() once
/// the source is ready, riding the detail-screen Play tap so it runs unmuted.
Widget buildPlayerView(String url, bool isHls) {
  final viewType = 'nascinema-video-${_counter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final video = web.HTMLVideoElement()..controls = false;
    video.style
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('background', 'black');
    _v = video;
    if (isHls) {
      _attachHls(video, url);
    } else {
      video.src = url;
      video.play();
    }
    return video;
  });
  return HtmlElementView(viewType: viewType);
}

// --- accessors the Flutter control bar polls / calls ----------------------

double playerCurrentTime() => _v?.currentTime ?? 0;

double playerDuration() {
  final d = _v?.duration ?? 0;
  return (d.isNaN || d.isInfinite) ? 0 : d;
}

bool playerPaused() => _v?.paused ?? true;

void playerSeek(double seconds) {
  final v = _v;
  if (v != null) v.currentTime = seconds;
}

void playerTogglePlay() {
  final v = _v;
  if (v == null) return;
  if (v.paused) {
    v.play();
  } else {
    v.pause();
  }
}

/// Flat [start, end, start, end, ...] of what the browser has buffered.
List<double> playerBuffered() {
  final v = _v;
  final out = <double>[];
  if (v != null) {
    final b = v.buffered;
    for (var i = 0; i < b.length; i++) {
      out
        ..add(b.start(i))
        ..add(b.end(i));
    }
  }
  return out;
}

double playerVolume() => _v?.volume ?? 1;

bool playerMuted() => _v?.muted ?? false;

void playerSetVolume(double v) {
  final el = _v;
  if (el != null) {
    el.volume = v.clamp(0.0, 1.0).toDouble();
    if (v > 0) el.muted = false;
  }
}

void playerToggleMute() {
  final el = _v;
  if (el != null) el.muted = !el.muted;
}

bool playerIsFullscreen() => web.document.fullscreenElement != null;

/// Fullscreen the whole page (not just the <video>) so our Flutter control bar
/// stays visible in fullscreen.
void playerToggleFullscreen() {
  if (web.document.fullscreenElement == null) {
    web.document.documentElement?.requestFullscreen();
  } else {
    web.document.exitFullscreen();
  }
}

JSFunction? _keyHandler;

/// Install window-level keyboard shortcuts. Window-level (not on the <video>)
/// so they work regardless of what has focus.
void installPlayerKeys() {
  removePlayerKeys();
  final h = ((web.Event e) {
    final el = _v;
    if (el == null) return;
    final key = (e as web.KeyboardEvent).key;
    switch (key) {
      case ' ':
      case 'k':
        e.preventDefault();
        if (el.paused) {
          el.play();
        } else {
          el.pause();
        }
        break;
      case 'ArrowLeft':
        e.preventDefault();
        final t = el.currentTime - 10;
        el.currentTime = t < 0 ? 0 : t;
        break;
      case 'ArrowRight':
        e.preventDefault();
        el.currentTime = el.currentTime + 10;
        break;
      case 'ArrowUp':
        e.preventDefault();
        el.volume = (el.volume + 0.1).clamp(0.0, 1.0).toDouble();
        el.muted = false;
        break;
      case 'ArrowDown':
        e.preventDefault();
        el.volume = (el.volume - 0.1).clamp(0.0, 1.0).toDouble();
        break;
      case 'f':
      case 'F':
        e.preventDefault();
        playerToggleFullscreen();
        break;
      case 'm':
      case 'M':
        e.preventDefault();
        el.muted = !el.muted;
        break;
    }
  }).toJS;
  _keyHandler = h;
  web.window.addEventListener('keydown', h);
}

void removePlayerKeys() {
  final h = _keyHandler;
  if (h != null) {
    web.window.removeEventListener('keydown', h);
    _keyHandler = null;
  }
}
