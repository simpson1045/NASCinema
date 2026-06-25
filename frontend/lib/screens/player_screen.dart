import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
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

  double _position = 0;
  double _duration = 0;
  bool _paused = true;
  List<double> _buffered = const [];
  List<List<double>> _cached = const [];
  Timer? _poll;
  Timer? _cachePoll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cachePoll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await ApiService(widget.baseUrl).getPlay(widget.fileId);
      if (!mounted) return;
      setState(() {
        _mode = p.mode;
        _reason = p.reason;
        // Built once — buildPlayerView registers a view factory per call.
        _player = buildPlayerView('${widget.baseUrl}${p.url}', p.mode != 'direct');
      });
      // Poll the video element for position/buffer, and the server for which
      // spans are converted, to drive the scrubber.
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        final d = playerDuration();
        setState(() {
          _position = playerCurrentTime();
          if (d > 0) _duration = d;
          _paused = playerPaused();
          _buffered = playerBuffered();
        });
      });
      _cachePoll =
          Timer.periodic(const Duration(seconds: 2), (_) => _refreshCached());
      _refreshCached();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
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
            Expanded(
              child: _player != null
                  ? _player!
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Could not start playback:\n$_error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: NasColors.bad)),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                              color: NasColors.amber)),
            ),
            if (_mode != null && _bannerVisible) _whyBanner(),
            if (_player != null) _controlBar(),
          ],
        ),
      ),
    );
  }

  Widget _controlBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(6, 2, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              playerTogglePlay();
              setState(() => _paused = playerPaused());
            },
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                color: Colors.white, size: 28),
          ),
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
}
