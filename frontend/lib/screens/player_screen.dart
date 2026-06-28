import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/cast/cast_device.dart';
import '../services/cast_actions.dart';
import '../services/cast_controller.dart';
import '../theme/app_theme.dart';
import 'cast_picker.dart';
import 'player/player_view.dart';
import 'player/scrubber.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.fileId,
    required this.baseUrl,
    required this.title,
  });

  final int fileId;
  final String baseUrl;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? _mode;
  String? _reason;
  String? _error;
  Widget? _player;
  bool _bannerVisible = true;

  String _playUrl = '';
  bool _isHls = false;
  // App-level Chromecast controller (survives navigation). Web → no-op stub.
  late final CastController _cast;

  // Stats for nerds: probed source facts (from the backend) + live client-side
  // playback facts (from the player engine), toggled by the info button.
  Map<String, dynamic> _source = const {};
  Map<String, String> _clientStats = const {};
  bool _statsVisible = false;

  // Native renderer: force lossless audio passthrough (bitstream to the AVR).
  static const _passthroughPrefKey = 'force_passthrough';
  bool _forcePassthrough = false;

  // The wired desktop renderer (ELKO) — the only libmpv direct-play client.
  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  double _position = 0;
  double _duration = 0;
  bool _paused = true;
  double _volume = 1;
  bool _muted = false;
  List<double> _buffered = const [];
  List<List<double>> _cached = const [];
  List<Map<String, dynamic>> _subs = [];
  String? _activeSub;
  double _subOffset = 0;
  bool _syncMode = false;
  Timer? _offsetSave;
  Timer? _poll;
  Timer? _cachePoll;
  Timer? _bannerTimer;

  // Resume: where to seek to + which subtitle to re-enable (from the backend),
  // applied once the player reports a duration. _saveTimer persists progress.
  double _resumePosition = 0;
  String? _resumeSubtitle;
  bool _resumeApplied = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _cast = context.read<CastController>();
    _load();
  }

  @override
  void dispose() {
    _saveProgress(); // capture the resume point on the way out
    _poll?.cancel();
    _cachePoll?.cancel();
    _offsetSave?.cancel();
    _bannerTimer?.cancel();
    _saveTimer?.cancel();
    removePlayerKeys();
    super.dispose();
  }

  /// Persist the local playback position + active subtitle for resume. Skips
  /// the very start/end so we don't clobber a good resume point with 0.
  void _saveProgress() {
    if (_duration <= 0 || _position <= 2) return;
    if (_position >= _duration - 5) return; // basically finished
    ApiService(widget.baseUrl).saveProgress(widget.fileId, _position, _activeSub);
  }

  Future<void> _load() async {
    try {
      // Only the wired DESKTOP renderer (ELKO) is the libmpv direct-play client.
      // Phone/tablet (and web) are browser-class → 'web' so the decision engine
      // transcodes what they can't natively play (HEVC/HDR/TrueHD).
      final p = await ApiService(widget.baseUrl)
          .getPlay(widget.fileId, client: _isDesktop ? 'native' : 'web');
      _resumePosition = p.resumePosition;
      _resumeSubtitle = p.resumeSubtitle;
      final passthrough = await _readPassthroughPref();
      if (!mounted) return;
      setForcePassthrough(passthrough); // applied when buildPlayerView opens
      setState(() {
        _mode = p.mode;
        _reason = p.reason;
        _playUrl = '${widget.baseUrl}${p.url}';
        _isHls = p.mode != 'direct';
        _source = p.source;
        _forcePassthrough = passthrough;
        // Built once — buildPlayerView registers a view factory per call.
        _player = buildPlayerView(_playUrl, _isHls);
      });
      // Poll the video element for position/buffer, and the server for which
      // spans are converted, to drive the scrubber.
      installPlayerKeys();
      // Auto-dismiss the "why am I transcoding" banner; it's informative, not a
      // nag — the user can still close it sooner with the x.
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _bannerVisible = false);
      });
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        final d = playerDuration();
        setState(() {
          _position = playerCurrentTime();
          if (d > 0) _duration = d;
          _paused = playerPaused();
          _buffered = playerBuffered();
          _volume = playerVolume();
          _muted = playerMuted();
          _clientStats = playerStats();
        });
        // Resume once the player knows its duration (so the seek lands).
        if (!_resumeApplied && _resumePosition > 2 && _duration > 0) {
          _resumeApplied = true;
          if (_resumePosition < _duration - 5) {
            playerSeek(_resumePosition);
            setState(() => _position = _resumePosition);
          }
        }
      });
      _cachePoll =
          Timer.periodic(const Duration(seconds: 2), (_) => _refreshCached());
      _refreshCached();
      // Persist the resume point periodically while watching.
      _saveTimer =
          Timer.periodic(const Duration(seconds: 15), (_) => _saveProgress());
      _loadSubs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSubs() async {
    try {
      final r = await ApiService(widget.baseUrl).getSubtitles(widget.fileId);
      if (!mounted) return;
      setState(() {
        _subs = r.subtitles;
        _subOffset = r.offset;
      });
      if (r.offset != 0) playerSetSubtitleOffset(r.offset);
      // Re-enable the subtitle the user had on last time, if it still exists.
      if (_resumeSubtitle != null && _activeSub == null) {
        for (final s in _subs) {
          if (s['id'] == _resumeSubtitle) {
            _selectSub(s);
            break;
          }
        }
      }
    } catch (_) {
      // best-effort
    }
  }

  void _nudgeSync(double delta) {
    setState(() =>
        _subOffset = double.parse((_subOffset + delta).toStringAsFixed(1)));
    playerSetSubtitleOffset(_subOffset);
    _offsetSave?.cancel();
    _offsetSave = Timer(const Duration(milliseconds: 600), () {
      ApiService(widget.baseUrl)
          .setSubtitleOffset(widget.fileId, _subOffset)
          .catchError((_) {});
    });
  }

  Future<void> _refreshCached() async {
    try {
      final c = await ApiService(widget.baseUrl).getCached(widget.fileId);
      if (!mounted) return;
      setState(() {
        _cached = c.ranges;
        if (_duration <= 0 && c.duration > 0) _duration = c.duration;
      });
    } catch (_) {
      // best-effort; the scrubber just won't show converted spans this tick
    }
  }

  Color get _modeColor => switch (_mode) {
        'direct' => NasColors.ok,
        'remux' => NasColors.violet,
        _ => NasColors.amber,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Column (not a Stack overlay): on web the HTML <video> platform view
      // swallows pointer events, so Flutter controls must sit beside it, not
      // on top, or the back/close buttons never receive taps.
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            if (_syncMode) _syncBar(),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _player != null
                      ? _player!
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('Could not start playback:\n$_error',
                                    textAlign: TextAlign.center,
                                    style:
                                        const TextStyle(color: NasColors.bad)),
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(
                                  color: NasColors.amber)),
                  if (_statsVisible)
                    Positioned(
                      top: 12,
                      left: 12,
                      // Display-only; never steal pointer events (matters on web,
                      // where the <video> platform view sits underneath).
                      child: IgnorePointer(child: _statsPanel()),
                    ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: (_mode != null && _bannerVisible)
                  ? KeyedSubtree(
                      key: const ValueKey('why'), child: _whyBanner())
                  : const SizedBox.shrink(),
            ),
            if (_player != null) _controlBar(),
          ],
        ),
      ),
    );
  }

  Widget _controlBar() {
    // Inline volume slider only where there's room; phones use hardware keys.
    final wide = MediaQuery.of(context).size.width > 520;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrubber on its own row so it never fights the buttons for width —
          // the old single-row bar overflowed on narrow (phone) screens.
          Row(
            children: [
              Text(_fmt(_position),
                  style: const TextStyle(color: NasColors.muted, fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(
                child: Scrubber(
                  duration: _duration,
                  position: _position,
                  buffered: _buffered,
                  cached: _cached,
                  onSeek: (s) {
                    playerSeek(s);
                    setState(() => _position = s);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(_fmt(_duration),
                  style: const TextStyle(color: NasColors.muted, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  playerTogglePlay();
                  setState(() => _paused = playerPaused());
                },
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white, size: 28),
              ),
              const Spacer(),
              IconButton(
                onPressed: _openSubsMenu,
                tooltip: 'Subtitles',
                icon: Icon(
                    _activeSub != null
                        ? Icons.closed_caption
                        : Icons.closed_caption_outlined,
                    color: _activeSub != null ? NasColors.amber : Colors.white,
                    size: 22),
              ),
              if (_cast.supported)
                AnimatedBuilder(
                  animation: _cast,
                  builder: (_, _) => IconButton(
                    onPressed: _cast.isConnected ? _doCast : _openCastSheet,
                    tooltip: 'Cast to TV',
                    icon: Icon(
                        _cast.isConnected ? Icons.cast_connected : Icons.cast,
                        color:
                            _cast.isConnected ? NasColors.amber : Colors.white,
                        size: 22),
                  ),
                ),
              IconButton(
                onPressed: () {
                  playerToggleMute();
                  setState(() => _muted = playerMuted());
                },
                icon: Icon(
                    (_muted || _volume == 0)
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 22),
              ),
              if (wide)
                SizedBox(
                  width: 84,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: NasColors.amber,
                      inactiveTrackColor: NasColors.surfaceRaised,
                      thumbColor: NasColors.amber,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value:
                          (_muted ? 0.0 : _volume).clamp(0.0, 1.0).toDouble(),
                      onChanged: (v) {
                        playerSetVolume(v);
                        setState(() {
                          _volume = v;
                          _muted = v == 0;
                        });
                      },
                    ),
                  ),
                ),
              if (_isDesktop)
                IconButton(
                  onPressed: _openAudioSettings,
                  tooltip: 'Audio passthrough',
                  icon: Icon(Icons.tune,
                      color:
                          _forcePassthrough ? NasColors.amber : Colors.white,
                      size: 22),
                ),
              IconButton(
                onPressed: () =>
                    setState(() => _statsVisible = !_statsVisible),
                tooltip: 'Stats for nerds',
                icon: Icon(Icons.info_outline,
                    color: _statsVisible ? NasColors.amber : Colors.white,
                    size: 22),
              ),
              IconButton(
                onPressed: playerToggleFullscreen,
                tooltip: 'Fullscreen (F)',
                icon: const Icon(Icons.fullscreen_rounded,
                    color: Colors.white, size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openCastSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => CastPicker(
        cast: _cast,
        onPick: (d) {
          Navigator.pop(context);
          _castTo(d);
        },
        onDisconnect: () {
          _cast.disconnect();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _castTo(CastDevice device) async {
    final ok = await _cast.connect(device);
    if (!ok || !mounted) return;
    await _doCast();
  }

  /// Cast the current movie to the TV and switch to the remote. Shared logic
  /// lives in [castFileToTv]; here we just pass the active subtitle along.
  Future<void> _doCast() async {
    await castFileToTv(
      context,
      cast: _cast,
      baseUrl: widget.baseUrl,
      fileId: widget.fileId,
      title: widget.title,
      activeSubtitleId: _activeSub,
    );
  }

  Future<bool> _readPassthroughPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_passthroughPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Renderer audio settings (native only): force lossless bitstream to the AVR.
  void _openAudioSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: _forcePassthrough,
                activeThumbColor: NasColors.amber,
                title: const Text('Force audio passthrough',
                    style: TextStyle(color: NasColors.text)),
                subtitle: const Text(
                    'Bitstream TrueHD/Atmos/DTS-HD straight to your AVR — no PC '
                    'decode. The thing Plex/JF won’t let you force. Applies '
                    'on the next play.',
                    style: TextStyle(color: NasColors.muted, fontSize: 12)),
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_passthroughPrefKey, v);
                  setForcePassthrough(v);
                  if (mounted) setState(() => _forcePassthrough = v);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _selectSub(Map<String, dynamic> sub) {
    playerSetSubtitle('${widget.baseUrl}${sub['url']}');
    setState(() => _activeSub = sub['id'] as String?);
  }

  void _subsOff() {
    playerClearSubtitle();
    setState(() => _activeSub = null);
  }

  Widget _syncBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          const Text('Subtitle sync',
              style: TextStyle(color: NasColors.muted, fontSize: 12)),
          const SizedBox(width: 10),
          _syncBtn('-0.5', () => _nudgeSync(-0.5)),
          _syncBtn('-0.1', () => _nudgeSync(-0.1)),
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            alignment: Alignment.center,
            child: Text(
                '${_subOffset >= 0 ? '+' : ''}${_subOffset.toStringAsFixed(1)}s',
                style: const TextStyle(
                    color: NasColors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          _syncBtn('+0.1', () => _nudgeSync(0.1)),
          _syncBtn('+0.5', () => _nudgeSync(0.5)),
          const Spacer(),
          if (_subOffset != 0)
            TextButton(
              onPressed: () => _nudgeSync(-_subOffset),
              child: const Text('Reset',
                  style: TextStyle(color: NasColors.muted)),
            ),
          TextButton(
            onPressed: () => setState(() => _syncMode = false),
            child:
                const Text('Done', style: TextStyle(color: NasColors.amber)),
          ),
        ],
      ),
    );
  }

  Widget _syncBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: const BorderSide(color: NasColors.surfaceRaised),
          foregroundColor: NasColors.text,
        ),
        child: Text(label),
      ),
    );
  }

  void _openSubsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _SubsSheet(
        baseUrl: widget.baseUrl,
        fileId: widget.fileId,
        subs: _subs,
        activeId: _activeSub,
        onOff: () {
          _subsOff();
          Navigator.pop(context);
        },
        onSelect: (s) {
          _selectSub(s);
          Navigator.pop(context);
        },
        onDownloaded: (s) {
          setState(() {
            if (!_subs.any((x) => x['id'] == s['id'])) {
              _subs = [..._subs, s];
            }
          });
          _selectSub(s);
          Navigator.pop(context);
        },
        onAdjustTiming: () {
          setState(() => _syncMode = true);
          Navigator.pop(context);
        },
      ),
    );
  }

  String _fmt(double s) {
    if (s.isNaN || s.isInfinite || s < 0) s = 0;
    final t = s.round();
    final h = t ~/ 3600;
    final m = (t % 3600) ~/ 60;
    final sec = t % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Widget _topBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _whyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NasColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _modeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_mode!.toUpperCase(),
                style: TextStyle(
                    color: _modeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_reason ?? '',
                style: const TextStyle(color: NasColors.text, fontSize: 12.5)),
          ),
          IconButton(
            onPressed: () => setState(() => _bannerVisible = false),
            icon: const Icon(Icons.close, color: NasColors.muted, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// "Stats for nerds": probed source facts (left of the slash, what's on disk)
  /// + live client facts (what the engine is actually outputting). The thing
  /// Plex/JF bury — surfaced in one glance.
  Widget _statsPanel() {
    String? str(String k) {
      final v = _source[k];
      return (v == null || '$v'.isEmpty) ? null : '$v';
    }

    final rows = <(String, String)>[('Playback', (_mode ?? '—').toUpperCase())];
    final w = _source['width'], h = _source['height'];
    final vbits = <String>[
      if (str('video_codec') != null) str('video_codec')!.toUpperCase(),
      if (w != null && h != null) '$w×$h',
      if (_source['hdr'] == true) 'HDR',
      if (_source['bit_depth'] != null) '${_source['bit_depth']}-bit',
    ];
    if (vbits.isNotEmpty) rows.add(('Source video', vbits.join(' · ')));
    if (str('audio_codec') != null) {
      rows.add(('Source audio', str('audio_codec')!.toUpperCase()));
    }
    if (str('container') != null) {
      rows.add(('Container', str('container')!.toUpperCase()));
    }
    _clientStats.forEach((k, v) => rows.add((k, v)));

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NasColors.surfaceRaised),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('STATS FOR NERDS',
                style: TextStyle(
                    color: NasColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(r.$1,
                        style: const TextStyle(
                            color: NasColors.muted, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(r.$2,
                        style: const TextStyle(
                            color: NasColors.text, fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubsSheet extends StatefulWidget {
  const _SubsSheet({
    required this.baseUrl,
    required this.fileId,
    required this.subs,
    required this.activeId,
    required this.onOff,
    required this.onSelect,
    required this.onDownloaded,
    required this.onAdjustTiming,
  });

  final String baseUrl;
  final int fileId;
  final List<Map<String, dynamic>> subs;
  final String? activeId;
  final VoidCallback onOff;
  final void Function(Map<String, dynamic>) onSelect;
  final void Function(Map<String, dynamic>) onDownloaded;
  final VoidCallback onAdjustTiming;

  @override
  State<_SubsSheet> createState() => _SubsSheetState();
}

class _SubsSheetState extends State<_SubsSheet> {
  bool _searchMode = false;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int? _downloadingOsId;

  Future<void> _runSearch() async {
    setState(() {
      _searchMode = true;
      _busy = true;
      _error = null;
      _results = [];
    });
    try {
      final r =
          await ApiService(widget.baseUrl).searchSubtitles(widget.fileId, 'en');
      if (mounted) {
        setState(() {
          _results = r;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Search failed — check the OpenSubtitles key';
          _busy = false;
        });
      }
    }
  }

  Future<void> _download(Map<String, dynamic> res) async {
    setState(() => _downloadingOsId = res['os_file_id'] as int?);
    try {
      final sub = await ApiService(widget.baseUrl).downloadSubtitle(
        widget.fileId,
        res['os_file_id'] as int,
        (res['language'] ?? 'und').toString(),
      );
      widget.onDownloaded(sub);
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadingOsId = null;
          _error = 'Download failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: _searchMode ? _buildSearch() : _buildList(),
      ),
    );
  }

  Widget _heading(String title, {Widget? leading}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
      child: Row(children: [
        if (leading != null) leading else const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: NasColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading('Subtitles'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_off_outlined,
                    color: NasColors.muted),
                title: const Text('Off', style: TextStyle(color: NasColors.text)),
                trailing: widget.activeId == null
                    ? const Icon(Icons.check, color: NasColors.amber)
                    : null,
                onTap: widget.onOff,
              ),
              for (final s in widget.subs)
                ListTile(
                  leading: const Icon(Icons.subtitles, color: NasColors.muted),
                  title: Text((s['label'] ?? 'Subtitle').toString(),
                      style: const TextStyle(color: NasColors.text)),
                  trailing: widget.activeId == s['id']
                      ? const Icon(Icons.check, color: NasColors.amber)
                      : null,
                  onTap: () => widget.onSelect(s),
                ),
              const Divider(height: 1, color: NasColors.surfaceRaised),
              ListTile(
                leading:
                    const Icon(Icons.av_timer_rounded, color: NasColors.text),
                title: const Text('Adjust timing…',
                    style: TextStyle(color: NasColors.text)),
                onTap: widget.onAdjustTiming,
              ),
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: NasColors.amber),
                title: const Text('Download subtitles…',
                    style: TextStyle(color: NasColors.amber)),
                onTap: _runSearch,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _heading('Download · English',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: NasColors.text),
              onPressed: () => setState(() => _searchMode = false),
            )),
        if (_busy)
          const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: NasColors.amber)),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: const TextStyle(color: NasColors.bad))),
        if (!_busy && _error == null && _results.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No subtitles found',
                  style: TextStyle(color: NasColors.muted))),
        if (!_busy && _error == null && _results.isNotEmpty)
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final hi = r['hearing_impaired'] == true;
                final downloading = _downloadingOsId == r['os_file_id'];
                return ListTile(
                  title: Text((r['release'] ?? 'Subtitle').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: NasColors.text, fontSize: 13)),
                  subtitle: Text(
                      '${(r['language'] ?? '').toString().toUpperCase()} · ${r['downloads'] ?? 0} downloads${hi ? ' · HI' : ''}',
                      style: const TextStyle(
                          color: NasColors.muted, fontSize: 11)),
                  trailing: downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: NasColors.amber))
                      : const Icon(Icons.download_rounded,
                          color: NasColors.muted, size: 20),
                  onTap: downloading ? null : () => _download(r),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Chromecast device picker. Kicks off mDNS discovery on open and lists devices
/// live via the controller's ChangeNotifier.
// (cast device picker extracted to cast_picker.dart — CastPicker)
