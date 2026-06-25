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

  Color get _modeColor => switch (_mode) {
        'direct' => NasColors.ok,
        'remux' => NasColors.violet,
        _ => NasColors.amber,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_player != null)
            Positioned.fill(child: _player!)
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not start playback:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NasColors.bad)),
              ),
            )
          else
            const Center(
                child: CircularProgressIndicator(color: NasColors.amber)),
          Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: _topBar())),
          if (_mode != null && _bannerVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(child: _whyBanner()),
            ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
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
