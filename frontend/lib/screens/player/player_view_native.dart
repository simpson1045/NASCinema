import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/fullscreen.dart' as shell;
import '../../services/gamepad/pad_button.dart';
import '../../services/mpv/embed_window.dart';
import '../../services/mpv/mpv_controller.dart';
import '../../services/theater/theater_control.dart';
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

// Tracks picked before Play (mpv ids, 1-based per type; sub 0 = off; null =
// the file's default). Set by the player screen before each launch.
int? _startAid;
int? _startSid;
void setStartTracks(int? audio, int? subtitle) {
  _startAid = audio;
  _startSid = subtitle;
}

// The player screen's hooks: our script-messages from uosc buttons/menus
// ("nascinema-versions", "nascinema-version <id>"), and what ▼ opens.
void Function(List<String> args)? _messageHandler;
void setPlayerMessageHandler(void Function(List<String> args)? h) =>
    _messageHandler = h;
void Function()? _versionsHandler;
void setVersionsHandler(void Function()? h) => _versionsHandler = h;

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

Widget _mpvBuild(String url) =>
    _MpvEmbedView(media: _playableDirect() ?? url, startAt: _startAt);

/// The direct NAS path only if this PC can actually open it (the share is
/// reachable and logged in); otherwise stream the URL. A path mpv can't load
/// used to leave a dead player screen.
String? _playableDirect() {
  final p = _directMedia;
  if (p == null) return null;
  try {
    if (File(p).existsSync()) return p;
  } catch (_) {}
  _diag('direct path not reachable, streaming instead: $p');
  return null;
}

/// The embedded video area: creates a native child window over exactly this
/// widget's rect, launches mpv into it (`--wid`), and keeps the child glued
/// to the rect through layout changes and window resizes. The Flutter chrome
/// around the rect (top bar, control bar) stays fully interactive — only the
/// video itself is native airspace.
class _MpvEmbedView extends StatefulWidget {
  const _MpvEmbedView({required this.media, required this.startAt});

  final String media;
  final double startAt;

  @override
  State<_MpvEmbedView> createState() => _MpvEmbedViewState();
}

// The live embed surface, reachable by the seam so player_screen can hide the
// native airspace while a modal overlay (subs menu, cast picker...) is open.
EmbedWindow? _embedWin;

class _MpvEmbedViewState extends State<_MpvEmbedView> {
  EmbedWindow? _win;
  bool _launching = false;
  bool _failed = false;
  Timer? _track;

  // mpv's on-video OSC is the player's control surface (the only overlay that
  // can live above the native airspace). Host-driven like the harness: show
  // on pointer activity, hide (with the cursor) after idle, stay while paused.
  bool _oscShown = false;
  Timer? _oscTimer;
  int _lastMouseMs = 0;

  void _pokeOsc() {
    if (!_oscShown) {
      _oscShown = true;
      _mpv?.setOscVisible(true);
      if (mounted) setState(() {});
    }
    _oscTimer?.cancel();
    _oscTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (_mpv?.paused == true) {
        _pokeOsc(); // pinned while paused; re-check in another cycle
        return;
      }
      _oscShown = false;
      _mpv?.setOscVisible(false);
      setState(() {});
    });
  }

  /// Forward pointer position to mpv (physical px, child-window-relative,
  /// throttled ~30/s — unthrottled mouse spam once deadlocked the harness).
  void _forwardMove(Offset local) {
    _pokeOsc();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < 33) return;
    _lastMouseMs = now;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    _mpv?.mouseMove((local.dx * dpr).round(), (local.dy * dpr).round());
  }

  @override
  void initState() {
    super.initState();
    // The rect only exists after the first layout; create everything then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    // Drift guard: layout usually rebuilds us on size changes, but position
    // shifts without a constraint change (e.g. a banner collapsing) don't.
    // A cheap rect check twice a second keeps the video glued in place.
    _track = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _syncBounds());
  }

  Rect? _physicalRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final origin = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(origin.dx * dpr, origin.dy * dpr,
        box.size.width * dpr, box.size.height * dpr);
  }

  Future<void> _create() async {
    if (_launching || !mounted) return;
    _launching = true;
    // Assemble the theater in parallel with the launch: Denon input/power,
    // C2 PC-label guard. (Refresh-rate match waits for the container fps.)
    unawaited(TheaterControl.instance.onPlayStarted(diag: _diag));
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final rect = _physicalRect();
    final win = rect == null ? null : EmbedWindow.create(rect);
    if (win == null) {
      _diag('embed window create failed');
      if (mounted) setState(() => _failed = true);
      return;
    }
    _win = win;
    _embedWin = win;
    final c = await MpvController.launch(
      media: widget.media,
      hwnd: win.hwnd,
      startSeconds: widget.startAt,
      passthrough: _forcePassthrough,
      audioId: _startAid,
      subId: _startSid,
      diag: _diag,
    );
    _mpv = c;
    if (c == null && mounted) setState(() => _failed = true);
    // mpv's window steals focus as it spawns — reclaim it so the app's
    // keyboard shortcuts (space/arrows/M) keep working.
    if (c != null) {
      win.focusApp();
      // uosc's fullscreen button → the app window's fullscreen.
      c.onFullscreenRequest = playerToggleFullscreen;
      // uosc's custom back button (script-message nascinema-back) → leave
      // the player screen, which tears everything down.
      c.events?.listen((e) {
        if (e['event'] != 'client-message') return;
        final args = [for (final a in (e['args'] as List? ?? const [])) '$a'];
        if (args.contains('nascinema-back')) {
          if (mounted) Navigator.of(context).maybePop();
        } else if (args.any((a) => a.startsWith('nascinema-'))) {
          _messageHandler?.call(args);
        }
      });
      // Tell people what the controller does (it's otherwise invisible).
      Timer(const Duration(milliseconds: 2500), () {
        if (_mpv == c) c.showHints(versions: _versionsHandler != null);
      });
      unawaited(_matchRefreshRate(c));
    }
    // Geometry truth into the log (letterbox debugging): our window chain +
    // mpv's own belief about its window/video size, at launch and settled.
    _diag('embed create rect=${rect!.left.round()},${rect.top.round()} '
        '${rect.width.round()}x${rect.height.round()} dpr=$dpr');
    for (final delay in const [5, 15]) {
      Future.delayed(Duration(seconds: delay), () async {
        if (mounted && _win != null) {
          final mpvView = await _mpv?.videoGeometry() ?? 'mpv gone';
          if (!mounted) return;
          // Flutter's own belief vs the win32 truth — if these disagree, the
          // "video draws at 2/3 size" bug lives in the window/view plumbing.
          final v = View.of(context);
          final fl = 'flutter-phys=${v.physicalSize.width.round()}x'
              '${v.physicalSize.height.round()} '
              'logical=${MediaQuery.sizeOf(context).width.round()}x'
              '${MediaQuery.sizeOf(context).height.round()}';
          _diag('embed geometry t+${delay}s: ${_win!.debugGeometry()} $mpvView $fl');
        }
      });
    }
  }

  /// Poll mpv for the container fps (known once demuxing starts), then hand
  /// it to the refresh-rate matcher. A mode change renegotiates HDMI, which
  /// can kill the exclusive audio endpoint — verify and reinit if needed.
  Future<void> _matchRefreshRate(MpvController c) async {
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || !c.running) return;
      final fps = await c.containerFps();
      if (fps == null || fps <= 0) continue;
      final changed =
          TheaterControl.instance.onFpsKnown(fps, diag: _diag);
      if (changed) {
        await Future.delayed(const Duration(seconds: 2));
        await c.ensureAudioAlive(diag: _diag);
      }
      return;
    }
    _diag('refresh: container-fps never reported — no match attempted');
  }

  void _syncBounds() {
    if (!mounted) return;
    final rect = _physicalRect();
    if (rect != null) _win?.setBounds(rect);
    // Also re-fit mpv's inner window: it appears a beat after launch and
    // never resizes itself, so the tracker owns its geometry.
    _win?.fitInner();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the child aligned right after every rebuild/layout pass too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBounds());
    // Pointer events over the video fall through the native windows (both
    // hit-test transparent) and land here — forward them to mpv so its OSC
    // is hoverable, clickable, and drag-scrubbable, exactly like the harness.
    return MouseRegion(
      cursor: _oscShown ? SystemMouseCursors.basic : SystemMouseCursors.none,
      onHover: (e) => _forwardMove(e.localPosition),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerHover: (e) => _forwardMove(e.localPosition),
        onPointerMove: (e) => _forwardMove(e.localPosition),
        onPointerDown: (e) {
          _forwardMove(e.localPosition);
          _mpv?.mouseLeftDown();
        },
        onPointerUp: (_) => _mpv?.mouseLeftUp(),
        child: Container(
          color: const Color(0xFF000000),
          alignment: Alignment.center,
          child: _failed
              ? const Text(
                  "Couldn't start the player.\nPress B to go back.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NasColors.text, fontSize: 28, height: 1.4),
                )
              : null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _track?.cancel();
    _oscTimer?.cancel();
    if (_embedWin == _win) _embedWin = null;
    _win?.destroy();
    _win = null;
    super.dispose();
  }
}

/// Modal overlays (subs sheet, cast picker, settings) can't composite above
/// the native video window — hide the video while one is up (audio continues)
/// and restore on dismiss. No-op on the media_kit leg (real texture, real
/// compositing).
void playerSetOverlayOpen(bool open) {
  if (_useMpv) _embedWin?.setVisible(!open);
}

/// Stats overlay: Flutter's panel can't draw above the native video, so the
/// mpv leg shows mpv's own in-video stats page instead. Returns true when
/// handled natively (the caller skips the Flutter panel).
bool playerToggleNativeStats() {
  if (!_useMpv) return false;
  _mpv?.toggleStatsOverlay();
  return true;
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

/// The subtitle the movie ended on: track id, 0 = off, null = unknown.
int? playerLastSubtitle() {
  final v = MpvController.lastSid;
  if (v == false) return 0;
  return v is num ? v.toInt() : null;
}

void playerResetLastSubtitle() {
  MpvController.lastSid = null;
  MpvController.lastSubFile = null;
}

/// The server subtitle id ("en-164365") the movie ended on, if any.
String? playerLastServerSubtitle() {
  final f = MpvController.lastSubFile;
  if (f == null || MpvController.lastSid == false) return null;
  final m = RegExp(r'/api/subtitles/\d+/file/([^/?#]+)\.vtt').firstMatch(f);
  return m?.group(1);
}

/// mpv is up and taking commands (it launches a beat after the screen).
bool playerReady() => _useMpv && (_mpv?.running ?? false);

/// Put a server subtitle in the native player's menu (no-op off mpv).
bool playerAddSubtitle(String url, String title, {String lang = 'und', bool select = false}) {
  if (!_useMpv || _mpv == null) return false;
  _mpv!.addSubtitle(url, title, lang: lang, select: select);
  return true;
}

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

// The embedded video tracks the app window, so the control-bar fullscreen
// button just drives the window itself (same as F11). media_kit leg (phone)
// has no window to toggle — harmless no-op there.
bool playerIsFullscreen() => false;
void playerToggleFullscreen() {
  if (_useMpv) shell.toggleFullscreen();
}

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
    // Give the desktop its refresh rate back (no-op if we never switched).
    TheaterControl.instance.onPlayStopped(diag: _diag);
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


// ---------------------------------------------------------------------------
// controller (Xbox pad) → the native player + its uosc UI
// ---------------------------------------------------------------------------

// Set when WE open a uosc menu, so the D-pad drives it even if uosc's
// menu-state property isn't observable on some build. Cleared on close.
bool _menuHint = false;

/// Drive the movie player from the controller. Returns true when handled;
/// false leaves the press to the screen (B = leave the player).
///
///   A play/pause · ←/→ skip 10 s · LB/RB chapter · X audio · Y subtitles ·
///   Start menu · ↑/↓ show the controls. With a menu open, the D-pad/A/B
///   navigate it instead.
bool playerPad(PadButton b) {
  final c = _mpv;
  if (!_useMpv || c == null || !c.running) {
    // No live player (it failed to start or exited): a stale "menu open" must
    // never swallow B — the player screen backs out.
    _menuHint = false;
    return false;
  }
  if (c.menuOpen || _menuHint) {
    const keys = {
      PadButton.up: 'UP', PadButton.down: 'DOWN',
      PadButton.left: 'LEFT', PadButton.right: 'RIGHT',
      PadButton.a: 'ENTER', PadButton.b: 'ESC',
    };
    final k = keys[b];
    if (k == null) return true; // swallow others while a menu is up
    c.keypress(k);
    if (b == PadButton.b || b == PadButton.a) _menuHint = false;
    return true;
  }
  switch (b) {
    case PadButton.a:
      c.togglePlay();
      c.uosc('flash-pause-indicator');
      c.uosc('flash-timeline');
    case PadButton.left:
      c.seekBy(-10);
      c.uosc('flash-timeline');
    case PadButton.right:
      c.seekBy(10);
      c.uosc('flash-timeline');
    case PadButton.lb:
      c.chapter(-1);
      c.uosc('flash-timeline');
    case PadButton.rb:
      c.chapter(1);
      c.uosc('flash-timeline');
    case PadButton.down when _versionsHandler != null:
      _menuHint = true;
      _versionsHandler!();
    case PadButton.up:
    case PadButton.down:
      // Just the timeline + the button legend — uosc's full UI (top bar,
      // mouse buttons, volume) is clutter on a controller.
      c.uosc('flash-timeline');
      c.showHints(versions: _versionsHandler != null);
    case PadButton.x:
      _menuHint = true;
      c.uosc('audio');
    case PadButton.y:
      _menuHint = true;
      c.uosc('subtitles');
    case PadButton.start:
      _menuHint = true;
      c.uosc('menu');
    default:
      return false;
  }
  return true;
}

/// Run a uosc binding on the live player (e.g. 'flash-top-bar').
void playerUosc(String binding) => _mpv?.uosc(binding);

/// Open a custom uosc menu on the live player (see MpvController.openMenu).
void playerOpenMenu(Map<String, Object?> menu) => _mpv?.openMenu(menu);

/// Language of the audio track playing now, if known.
Future<String?> playerCurrentAudioLang() async =>
    await _mpv?.currentAudioLang();

/// Switch the live player to another file (another version) in place.
void playerLoadMedia(String media, {double start = 0, String? alang}) =>
    _mpv?.loadFile(media, start: start, alang: alang);
