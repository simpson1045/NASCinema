import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/mpv/mpv_controller.dart';
import '../../theme/app_theme.dart';

/// Native player seam — two legs behind one API:
///
///  * **Windows (the wired renderer, ELKO):** native `mpv.exe` driven over
///    JSON IPC. media_kit's ANGLE texture path cannot render 4K HDR Dolby
///    Vision there; native mpv's own d3d11/gpu-next pipeline can, plus
///    lossless TrueHD/Atmos bitstream (proven on the C2 + Denon — memories
///    `elko-renderer-is-native-mpv`, `mpv-wid-embed-ipc-architecture`).
///    M1: mpv opens its own fullscreen window; M2 embeds it in the app
///    window via `--wid`.
///  * **Android/iOS (the phone):** media_kit/libmpv in-texture, as before.
///
/// Every function mirrors the web player's accessors one-for-one so
/// `player_screen.dart` drives all legs through the same calls.

bool get _useMpv => Platform.isWindows;

// ---------------------------------------------------------------------------
// shared seam state
// ---------------------------------------------------------------------------

// Opt-in lossless audio passthrough (persisted by the player screen). OFF by
// default: exclusive WASAPI + spdif on a device that can't bitstream silences
// audio; the user enables it on the wired renderer where the AVR decodes it.
bool _forcePassthrough = false;
void setForcePassthrough(bool on) => _forcePassthrough = on;

// Direct-play source path (UNC) from the play decision, for native clients.
// The renderer reads the NAS file directly — the proven flawless byte path —
// instead of round-tripping through the backend's HTTP stream. Null → play
// the URL the seam is handed (backend stream), which remains the fallback.
String? _directMedia;
void setDirectMedia(String? path) => _directMedia = path;

// Where to start playback (resume point), applied at launch on the mpv leg so
// we don't open at 0:00 and visibly jump. media_kit leg resumes via seek.
double _startAt = 0;
void setStartPosition(double seconds) => _startAt = seconds;

/// Append a diagnostic line next to the running exe. ELKO (the renderer) has
/// no remote shell, so this is how we read player failures — over the C$
/// share. Best-effort; never throws into playback.
void _diag(String line) {
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    File('$dir${Platform.pathSeparator}nascinema_player.log')
        .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

Widget buildPlayerView(String url, bool isHls) =>
    _useMpv ? _mpvBuild(url) : _mkBuild(url);

// ---------------------------------------------------------------------------
// mpv leg (Windows renderer)
// ---------------------------------------------------------------------------

MpvController? _mpv;
String _mpvStatus = 'Starting renderer…';

Widget _mpvBuild(String url) {
  final media = _directMedia ?? url;
  _mpvStatus = 'Starting renderer…';
  // Fire-and-forget: the seam API is synchronous; accessors read the
  // controller's mirrored state (zeros until mpv reports in).
  () async {
    final c = await MpvController.launch(
      media: media,
      startSeconds: _startAt,
      passthrough: _forcePassthrough,
      diag: _diag,
    );
    _mpv = c;
    _mpvStatus = c == null
        ? 'Renderer failed to start — see nascinema_player.log'
        : 'Playing on the renderer';
  }();

  // M1 placeholder — mpv renders in its own fullscreen window; this fills the
  // app's video slot behind it. M2 replaces it with the embedded video area.
  return Container(
    color: const Color(0xFF000000),
    alignment: Alignment.center,
    child: Text(
      _mpvStatus,
      style: const TextStyle(color: NasColors.muted, fontSize: 14),
    ),
  );
}

// ---------------------------------------------------------------------------
// media_kit leg (phone/tablet)
// ---------------------------------------------------------------------------

bool _mkInit = false;
Player? _player;

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

Widget _mkBuild(String url) {
  _ensureInit();
  // New title — tear down any prior libmpv instance (and its audio device)
  // before opening the next, so we never leak an exclusive WASAPI handle.
  _disposePlayer();

  final player = Player();
  final controller = VideoController(player);
  _player = player;
  _muted = false;
  _volBeforeMute = 100;

  player.stream.error.listen((e) => _diag('ERROR: $e'));
  _diag('open (media_kit): $url');

  // mpv plays HLS and plain files alike; `isHls` is irrelevant here. open()
  // autoplays, riding the detail-screen Play tap like the web leg.
  player.open(Media(url));

  return Video(controller: controller, controls: NoVideoControls);
}

// ---------------------------------------------------------------------------
// accessors the Flutter control bar polls / calls
// ---------------------------------------------------------------------------

double playerCurrentTime() => _useMpv
    ? (_mpv?.position ?? 0)
    : (_player?.state.position.inMilliseconds ?? 0) / 1000;

double playerDuration() => _useMpv
    ? (_mpv?.duration ?? 0)
    : (_player?.state.duration.inMilliseconds ?? 0) / 1000;

bool playerPaused() =>
    _useMpv ? (_mpv?.paused ?? true) : !(_player?.state.playing ?? false);

void playerSeek(double seconds) {
  if (_useMpv) {
    _mpv?.seek(seconds);
  } else {
    _player?.seek(Duration(milliseconds: (seconds * 1000).round()));
  }
}

void playerTogglePlay() =>
    _useMpv ? _mpv?.togglePlay() : _player?.playOrPause();

/// Flat [start, end] of buffered content. mpv exposes a single buffered-until
/// position (demuxer-cache-time), not disjoint ranges — one span from 0.
List<double> playerBuffered() {
  if (_useMpv) {
    final b = _mpv?.cacheTime ?? 0;
    return b > 0 ? [0, b] : const [];
  }
  final p = _player;
  if (p == null) return const [];
  final b = p.state.buffer.inMilliseconds / 1000;
  return b > 0 ? [0, b] : const [];
}

double playerVolume() =>
    _useMpv ? (_mpv?.volume ?? 100) / 100 : (_player?.state.volume ?? 100) / 100;

bool playerMuted() => _useMpv ? (_mpv?.muted ?? false) : _muted;

void playerSetVolume(double v) {
  final vv = v.clamp(0.0, 1.0).toDouble();
  if (_useMpv) {
    _mpv?.setVolume(vv);
    return;
  }
  final p = _player;
  if (p == null) return;
  p.setVolume(vv * 100);
  if (vv > 0) _muted = false;
}

void playerToggleMute() {
  if (_useMpv) {
    _mpv?.toggleMute();
    return;
  }
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

// The renderer runs full-screen on the TV; the app-window fullscreen toggle
// lives in the shell (window_manager). No-op here so the button is harmless.
bool playerIsFullscreen() => false;
void playerToggleFullscreen() {}

bool _onKey(KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
  final k = e.logicalKey;
  if (!_useMpv && _player == null) return false;
  if (_useMpv && _mpv == null) return false;
  if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
    playerTogglePlay();
    return true;
  }
  if (k == LogicalKeyboardKey.arrowLeft) {
    final t = playerCurrentTime() - 10;
    playerSeek(t < 0 ? 0 : t);
    return true;
  }
  if (k == LogicalKeyboardKey.arrowRight) {
    playerSeek(playerCurrentTime() + 10);
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
/// release the player and the exclusive audio device here, not just the keys.
void removePlayerKeys() {
  HardwareKeyboard.instance.removeHandler(_onKey);
  if (_useMpv) {
    final c = _mpv;
    _mpv = null;
    c?.dispose();
  } else {
    _disposePlayer();
  }
}

void playerSetSubtitle(String url) => _useMpv
    ? _mpv?.setSubtitleUri(url)
    : _player?.setSubtitleTrack(SubtitleTrack.uri(url));

void playerClearSubtitle() => _useMpv
    ? _mpv?.clearSubtitle()
    : _player?.setSubtitleTrack(SubtitleTrack.no());

/// Positive = subs shown later, matching the web cue-shift sign.
void playerSetSubtitleOffset(double seconds) {
  if (_useMpv) {
    _mpv?.setSubDelay(seconds);
    return;
  }
  final p = _player?.platform;
  if (p is NativePlayer) p.setProperty('sub-delay', seconds.toString());
}

/// Runtime playback facts for the "stats for nerds" overlay — what the engine
/// is actually doing right now (vs the probed source the backend reports).
Map<String, String> playerStats() {
  if (_useMpv) return _mpv?.stats() ?? const {};
  final p = _player;
  if (p == null) return const {};
  final s = p.state;
  final out = <String, String>{'Engine': 'libmpv (media_kit)'};
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
