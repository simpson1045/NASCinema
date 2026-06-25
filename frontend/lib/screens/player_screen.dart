import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'player/player_view.dart';

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
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _load();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _unmute() {
    setPlayerMuted(false);
    setState(() => _muted = false);
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
            if (_player != null && _muted) _unmuteBanner(),
            if (_mode != null && _bannerVisible) _whyBanner(),
          ],
        ),
      ),
    );
  }

  Widget _unmuteBanner() {
    return Material(
      color: NasColors.amber,
      child: InkWell(
        onTap: _unmute,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.volume_off_rounded, color: NasColors.bg, size: 20),
              SizedBox(width: 10),
              Text('Audio is muted — tap to unmute',
                  style: TextStyle(
                      color: NasColors.bg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
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
