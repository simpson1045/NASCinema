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
  double _volume = 1;
  bool _muted = false;
  List<double> _buffered = const [];
  List<List<double>> _cached = const [];
  List<Map<String, dynamic>> _subs = [];
  String? _activeSub;
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
    removePlayerKeys();
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
      installPlayerKeys();
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
        });
      });
      _cachePoll =
          Timer.periodic(const Duration(seconds: 2), (_) => _refreshCached());
      _refreshCached();
      _loadSubs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSubs() async {
    try {
      final subs = await ApiService(widget.baseUrl).getSubtitles(widget.fileId);
      if (mounted) setState(() => _subs = subs);
    } catch (_) {
      // best-effort
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
          const SizedBox(width: 4),
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
          SizedBox(
            width: 84,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: NasColors.amber,
                inactiveTrackColor: NasColors.surfaceRaised,
                thumbColor: NasColors.amber,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: (_muted ? 0.0 : _volume).clamp(0.0, 1.0).toDouble(),
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
          IconButton(
            onPressed: playerToggleFullscreen,
            tooltip: 'Fullscreen (F)',
            icon: const Icon(Icons.fullscreen_rounded,
                color: Colors.white, size: 24),
          ),
        ],
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

class _SubsSheet extends StatefulWidget {
  const _SubsSheet({
    required this.baseUrl,
    required this.fileId,
    required this.subs,
    required this.activeId,
    required this.onOff,
    required this.onSelect,
    required this.onDownloaded,
  });

  final String baseUrl;
  final int fileId;
  final List<Map<String, dynamic>> subs;
  final String? activeId;
  final VoidCallback onOff;
  final void Function(Map<String, dynamic>) onSelect;
  final void Function(Map<String, dynamic>) onDownloaded;

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
