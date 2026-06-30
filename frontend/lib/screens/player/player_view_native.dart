import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native ELKO renderer: libmpv via media_kit. This is the flagship leg of the
/// player seam (the web/hls.js file is the fallback). It direct-plays the
/// original file from `/api/stream/{id}/direct`, bitstreams lossless audio to
/// the AVR, and renders embedded/sidecar subs natively (no burn-in).
///
/// Every function here mirrors the web player's accessors one-for-one so
/// `player_screen.dart` drives both legs through the same calls.

bool _mkInit = false;
Player? _player;

// Opt-in lossless audio passthrough (set from renderer settings, persisted by
// the player screen). OFF by default: forcing exclusive WASAPI + spdif on an
// output device that can't bitstream silences or halts audio, so the user turns
// it on only on the wired renderer (ELKO) where the AVR can decode it.
const _spdifCodecs = 'ac3,dts,eac3,truehd,dts-hd,dts-hd-ma';
bool _forcePassthrough = false;
void setForcePassthrough(bool on) => _forcePassthrough = on;

// media_kit has no mute flag; we emulate it by zeroing volume and remembering
// the level to restore, matching the web <video>.muted semantics.
bool _muted = false;
double _volBeforeMute = 100;

void _ensureInit() {
  if (_mkInit) return;
  MediaKit.ensureInitialized();
  _mkInit = true;
}

void _disposePlayer() {
  final p = _player;
  _player = null;
  p?.dispose();
}

/// Append a diagnostic line next to the running exe. ELKO (the renderer) has no
/// remote shell, so this is how we read libmpv failures — over the C$ share.
/// Best-effort; never throws into playback.
void _diag(String line) {
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    File('$dir${Platform.pathSeparator}nascinema_player.log')
        .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

Widget buildPlayerView(String url, bool isHls) {
  _ensureInit();
  // New title — tear down any prior libmpv instance (and its audio device)
  // before opening the next, so we never leak an exclusive WASAPI handle.
  _disposePlayer();

  final player = Player();
  final controller = VideoController(player);
  _player = player;
  _muted = false;
  _volBeforeMute = 100;

  // Surface failures off-box (ELKO has no shell): log the open + any libmpv
  // error next to the exe, readable over the C$ share.
  player.stream.error.listen((e) => _diag('ERROR: $e'));
  // Capture libmpv's own audio-output negotiation (which device, which format,
  // did the spdif bitstream get accepted) so we can see why passthrough is
  // silent. Read over the C$ share. Diagnostic — trim once audio is solved.
  player.stream.log.listen((l) => _diag('mpv[${l.level}] ${l.prefix}: ${l.text}'));
  _diag('open: $url (passthrough=$_forcePassthrough)');

  // Lossless audio passthrough when the user has forced it: take exclusive
  // control of the output device and bitstream the listed codecs straight to
  // the AVR. Audio bypasses the Flutter texture, so it works even though video
  // is composited. Off by default (see _forcePassthrough).
  final platform = player.platform;
  if (platform is NativePlayer) {
    // Verbose audio-output + decoder logs so the C$ log shows the actual device
    // and format negotiation (diagnostic).
    platform.setProperty('msg-level', 'ao=v,ad=v,af=v');
    if (_forcePassthrough) {
      platform.setProperty('audio-exclusive', 'yes');
      platform.setProperty('audio-spdif', _spdifCodecs);
    }
  }

  // mpv plays HLS and plain files alike; `isHls` is irrelevant here. open()
  // autoplays, riding the detail-screen Play tap like the web leg.
  player.open(Media(url));

  return Video(controller: controller, controls: NoVideoControls);
}

// --- accessors the Flutter control bar polls / calls ----------------------

double playerCurrentTime() =>
    (_player?.state.position.inMilliseconds ?? 0) / 1000;

double playerDuration() => (_player?.state.duration.inMilliseconds ?? 0) / 1000;

bool playerPaused() => !(_player?.state.playing ?? false);

void playerSeek(double seconds) =>
    _player?.seek(Duration(milliseconds: (seconds * 1000).round()));

void playerTogglePlay() => _player?.playOrPause();

/// Flat [start, end] of buffered content. libmpv exposes a single buffered
/// duration, not disjoint ranges, so we report one span from 0.
List<double> playerBuffered() {
  final p = _player;
  if (p == null) return const [];
  final b = p.state.buffer.inMilliseconds / 1000;
  return b > 0 ? [0, b] : const [];
}

double playerVolume() => (_player?.state.volume ?? 100) / 100;

bool playerMuted() => _muted;

void playerSetVolume(double v) {
  final p = _player;
  if (p == null) return;
  final vv = v.clamp(0.0, 1.0).toDouble();
  p.setVolume(vv * 100);
  if (vv > 0) _muted = false;
}

void playerToggleMute() {
  final p = _player;
  if (p == null) return;
  if (_muted) {
    p.setVolume(_volBeforeMute);
    _muted = false;
  } else {
    _volBeforeMute = p.state.volume;
    p.setVolume(0);
    _muted = true;
  }
}

// Desktop renderer runs full-screen on the TV; an in-app fullscreen toggle
// needs window_manager wiring (follow-up). No-op for now so the control-bar
// button is harmless.
bool playerIsFullscreen() => false;
void playerToggleFullscreen() {}

bool _onKey(KeyEvent e) {
  final p = _player;
  if (p == null) return false;
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
  final k = e.logicalKey;
  if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
    p.playOrPause();
    return true;
  }
  if (k == LogicalKeyboardKey.arrowLeft) {
    final t = p.state.position - const Duration(seconds: 10);
    p.seek(t < Duration.zero ? Duration.zero : t);
    return true;
  }
  if (k == LogicalKeyboardKey.arrowRight) {
    p.seek(p.state.position + const Duration(seconds: 10));
    return true;
  }
  if (k == LogicalKeyboardKey.arrowUp) {
    playerSetVolume(playerVolume() + 0.1);
    return true;
  }
  if (k == LogicalKeyboardKey.arrowDown) {
    playerSetVolume(playerVolume() - 0.1);
    return true;
  }
  if (k == LogicalKeyboardKey.keyM) {
    playerToggleMute();
    return true;
  }
  return false;
}

void installPlayerKeys() => HardwareKeyboard.instance.addHandler(_onKey);

/// Also the screen's teardown hook (player_screen calls this from dispose) —
/// release libmpv and the exclusive audio device here, not just the keys.
void removePlayerKeys() {
  HardwareKeyboard.instance.removeHandler(_onKey);
  _disposePlayer();
}

void playerSetSubtitle(String url) =>
    _player?.setSubtitleTrack(SubtitleTrack.uri(url));

void playerClearSubtitle() => _player?.setSubtitleTrack(SubtitleTrack.no());

/// Positive = subs shown later, matching the web cue-shift sign.
void playerSetSubtitleOffset(double seconds) {
  final p = _player?.platform;
  if (p is NativePlayer) p.setProperty('sub-delay', seconds.toString());
}

/// Runtime playback facts for the "stats for nerds" overlay — what libmpv is
/// actually doing right now (vs the probed source the backend reports).
Map<String, String> playerStats() {
  final p = _player;
  if (p == null) return const {};
  final s = p.state;
  final out = <String, String>{'Engine': 'libmpv (native, direct)'};
  if ((s.width ?? 0) > 0 && (s.height ?? 0) > 0) {
    out['Video out'] = '${s.width}×${s.height}';
  }
  final ap = s.audioParams;
  final aud = <String>[];
  if (ap.format != null && ap.format!.isNotEmpty) aud.add(ap.format!);
  if ((ap.sampleRate ?? 0) > 0) {
    aud.add('${(ap.sampleRate! / 1000).toStringAsFixed(1)} kHz');
  }
  if ((ap.channelCount ?? 0) > 0) aud.add('${ap.channelCount} ch');
  if (aud.isNotEmpty) out['Audio out'] = aud.join(' · ');
  if ((s.audioBitrate ?? 0) > 0) {
    out['Audio bitrate'] = '${(s.audioBitrate! / 1000).round()} kbps';
  }
  return out;
}
