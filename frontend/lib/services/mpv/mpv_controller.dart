/// Native mpv renderer controller (Windows): launches `mpv.exe` with the
/// ELKO-proven flag set, drives it over JSON IPC, and mirrors playback state
/// locally so the player seam's synchronous accessors can poll it.
///
/// Why a separate process and not libmpv-in-texture: media_kit's ANGLE
/// texture path cannot render 4K HDR Dolby Vision on the renderer PC. Native
/// mpv with its own d3d11/gpu-next pipeline can — proven flawless on the
/// C2 + Denon (see memories `elko-renderer-is-native-mpv`,
/// `mpv-exclusive-buffer-fixes-passthrough-crackle`,
/// `mpv-wid-embed-ipc-architecture`).
library;

import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'mpv_ipc.dart';

/// Everything is config, not constants (multi-user & topology-agnostic):
/// these are just the defaults a fresh renderer install starts from.
const kMpvPathPref = 'mpv_path';
const kMpvDefaultPath = r'C:\Program Files\MPV Player\mpv.exe';

class MpvController {
  MpvController._();

  static MpvController? _live;

  Process? _proc;
  MpvIpc? _ipc;
  bool _disposed = false;

  // --- mirrored playback state (updated by observe events) ------------------
  double position = 0;
  double duration = 0;
  bool paused = false;
  double volume = 100; // mpv scale 0..100
  bool muted = false;
  double cacheTime = 0; // demuxer-cache-time: absolute buffered-until position
  bool eofReached = false;
  int? videoW;
  int? videoH;
  String audioFormat = '';
  int audioRate = 0;
  int audioChannels = 0;
  double audioBitrate = 0;
  String hwdec = '';

  bool get running => _ipc != null && !_disposed;

  /// Launch mpv playing [media] (UNC path or URL). If [hwnd] is given the
  /// video embeds into that native child window (`--wid`); otherwise mpv
  /// opens its own fullscreen window (the M1 stepping stone).
  ///
  /// [passthrough] wires the verified lossless chain: WASAPI exclusive +
  /// spdif bitstream + the 100 ms exclusive buffer that killed the
  /// loud-peak crackle. Off = mpv's normal shared-mode PCM output.
  static Future<MpvController?> launch({
    required String media,
    int? hwnd,
    double startSeconds = 0,
    bool passthrough = false,
    void Function(String line)? diag,
  }) async {
    // One renderer at a time — tear down the previous instance (and its
    // exclusive audio device) before opening the next.
    await _live?.dispose();

    final prefs = await SharedPreferences.getInstance();
    final mpvPath = prefs.getString(kMpvPathPref) ?? kMpvDefaultPath;
    if (!File(mpvPath).existsSync()) {
      diag?.call('mpv not found at $mpvPath (set $kMpvPathPref)');
      return null;
    }

    final pipeName = 'nascinema-mpv-${DateTime.now().millisecondsSinceEpoch}';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final args = <String>[
      '--input-ipc-server=\\\\.\\pipe\\$pipeName',
      // No console output: Process.start pipes stdout/stderr, and an undrained
      // pipe BLOCKS mpv's core mid-startup (black frozen window — happened
      // live). Diagnostics go to a log file next to the exe instead.
      '--terminal=no',
      '--log-file=$exeDir${Platform.pathSeparator}mpv.log',
      if (hwnd != null) '--wid=$hwnd' else '--fullscreen',
      if (startSeconds > 1) '--start=$startSeconds',
      '--hwdec=auto',
      '--keep-open=yes', // reaching EOF must not kill the process under us
      '--force-window=yes',
      if (hwnd != null) ...[
        // Embedded: the app owns input and forwards over IPC — don't let
        // mpv's child window grab keys and double-handle them.
        '--input-default-bindings=no',
        '--input-vo-keyboard=no',
        '--osc=no',
      ] else ...[
        // Own-window (M1 stepping stone): mpv keeps its native keys + OSC so
        // the fullscreen window is controllable directly.
        '--osc=yes',
      ],
      '--osd-level=1',
      if (passthrough) ...[
        '--audio-spdif=truehd,dts-hd,eac3,ac3',
        '--audio-exclusive=yes',
        '--wasapi-exclusive-buffer=100000',
        '--audio-buffer=1.0',
      ],
      // Big demuxer cache: smooth network direct-play, instant sub switches.
      '--cache=yes',
      '--demuxer-max-bytes=1GiB',
      '--demuxer-max-back-bytes=512MiB',
      '--demuxer-readahead-secs=60',
      media,
    ];

    diag?.call('mpv launch: $mpvPath ${args.join(' ')}');
    final c = MpvController._();
    try {
      c._proc = await Process.start(mpvPath, args);
      // Drain stdout/stderr even with --terminal=no — an undrained child pipe
      // filling up blocks the child process. Never rely on "it won't write".
      c._proc!.stdout.listen((_) {});
      c._proc!.stderr.listen((_) {});
    } catch (e) {
      diag?.call('mpv spawn failed: $e');
      return null;
    }

    c._ipc = await MpvIpc.connect(pipeName);
    if (c._ipc == null) {
      diag?.call('mpv IPC connect timed out (pipe $pipeName)');
      c._proc?.kill();
      return null;
    }

    c._wireObservers();
    // If mpv exits on its own (crash, user Alt+F4 on the window), reflect it.
    c._ipc!.done.then((_) => c._disposed = true);
    unawaited(c._proc!.exitCode.then((code) {
      diag?.call('mpv exited ($code)');
      c._disposed = true;
    }));

    _live = c;
    return c;
  }

  void _wireObservers() {
    final ipc = _ipc!;
    ipc.observe('time-pos', (v) => position = (v as num?)?.toDouble() ?? position);
    ipc.observe('duration', (v) => duration = (v as num?)?.toDouble() ?? 0);
    ipc.observe('pause', (v) => paused = v == true);
    ipc.observe('volume', (v) => volume = (v as num?)?.toDouble() ?? volume);
    ipc.observe('mute', (v) => muted = v == true);
    ipc.observe('demuxer-cache-time',
        (v) => cacheTime = (v as num?)?.toDouble() ?? 0);
    ipc.observe('eof-reached', (v) => eofReached = v == true);
    ipc.observe('video-params', (v) {
      if (v is Map) {
        videoW = (v['w'] as num?)?.toInt();
        videoH = (v['h'] as num?)?.toInt();
      }
    });
    ipc.observe('audio-params', (v) {
      if (v is Map) {
        audioFormat = v['format']?.toString() ?? '';
        audioRate = (v['samplerate'] as num?)?.toInt() ?? 0;
        audioChannels = (v['channel-count'] as num?)?.toInt() ?? 0;
      }
    });
    ipc.observe('audio-bitrate',
        (v) => audioBitrate = (v as num?)?.toDouble() ?? 0);
    ipc.observe('hwdec-current', (v) => hwdec = v?.toString() ?? '');
  }

  // --- controls (the seam + the phone remote both land here) ----------------

  void seek(double seconds) =>
      _ipc?.command(['seek', seconds, 'absolute', 'exact']);

  void togglePlay() => _ipc?.command(['cycle', 'pause']);

  void setPaused(bool p) => _ipc?.set('pause', p);

  /// 0..1 like the web `<video>`; mpv wants 0..100.
  void setVolume(double v01) =>
      _ipc?.set('volume', (v01.clamp(0.0, 1.0) * 100).round());

  void toggleMute() => _ipc?.command(['cycle', 'mute']);

  /// Load a sidecar subtitle (backend WebVTT URL) and select it.
  void setSubtitleUri(String url) =>
      _ipc?.command(['sub-add', url, 'select']);

  void clearSubtitle() => _ipc?.set('sid', 'no');

  /// Positive = subs shown later (matches the web player's cue-shift sign).
  void setSubDelay(double seconds) => _ipc?.set('sub-delay', seconds);

  /// One-off OSD text (amber-themed later; used for connect toasts / debug).
  void showText(String text, {int ms = 2000}) =>
      _ipc?.command(['show-text', text, ms]);

  Map<String, String> stats() {
    final out = <String, String>{'Engine': 'mpv (native, direct)'};
    if ((videoW ?? 0) > 0 && (videoH ?? 0) > 0) {
      out['Video out'] = '$videoW×$videoH';
    }
    if (hwdec.isNotEmpty && hwdec != 'no') out['Hwdec'] = hwdec;
    final aud = <String>[];
    if (audioFormat.isNotEmpty) aud.add(audioFormat);
    if (audioRate > 0) aud.add('${(audioRate / 1000).toStringAsFixed(1)} kHz');
    if (audioChannels > 0) aud.add('$audioChannels ch');
    if (aud.isNotEmpty) out['Audio out'] = aud.join(' · ');
    if (audioBitrate > 0) {
      out['Audio bitrate'] = '${(audioBitrate / 1000).round()} kbps';
    }
    return out;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_live == this) _live = null;
    try {
      await _ipc?.quit();
    } catch (_) {}
    // Belt & braces: if quit didn't land, kill — we must never leak a process
    // holding the exclusive audio device.
    final p = _proc;
    if (p != null) {
      final died = await p.exitCode
          .timeout(const Duration(seconds: 3), onTimeout: () => -1);
      if (died == -1) p.kill(ProcessSignal.sigkill);
    }
  }
}
