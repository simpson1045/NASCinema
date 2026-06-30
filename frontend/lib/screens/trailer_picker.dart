import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/video.dart';
import '../services/api_service.dart';

/// Pick which trailer a movie uses on every device (Roku included). Lists TMDB's
/// trailers with an in-app preview, accepts a manual YouTube/other URL, and saves
/// the choice to the backend's `trailer_youtube` override.
class TrailerPicker extends StatefulWidget {
  const TrailerPicker({
    super.key,
    required this.api,
    required this.movieId,
    required this.title,
    required this.videos,
    this.currentPin,
  });

  final ApiService api;
  final int movieId;
  final String title;
  final List<Video> videos;
  final String? currentPin;

  @override
  State<TrailerPicker> createState() => _TrailerPickerState();
}

class _TrailerPickerState extends State<TrailerPicker> {
  late final YoutubePlayerController _player;
  final _manualCtrl = TextEditingController();
  String? _pin; // currently saved override (url or key)
  String? _previewKey; // what's loaded in the player
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pin = widget.currentPin;
    _player = YoutubePlayerController(
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    // Preview the pinned trailer (or the first listed) on open.
    final first = _keyOf(_pin) ??
        (widget.videos.isNotEmpty ? widget.videos.first.key : null);
    if (first != null && first.isNotEmpty) {
      _previewKey = first;
      _player.loadVideoById(videoId: first);
    }
  }

  @override
  void dispose() {
    _player.close();
    _manualCtrl.dispose();
    super.dispose();
  }

  /// Extract a YouTube id from a URL or bare key (matches the backend).
  String? _keyOf(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;
    if (s.contains('watch?v=')) return s.split('watch?v=')[1].split('&')[0];
    if (s.contains('youtu.be/')) return s.split('youtu.be/')[1].split('?')[0];
    if (s.contains('/')) return s.split('/').last.split('?')[0];
    return s;
  }

  void _preview(String key) {
    if (key.isEmpty) return;
    setState(() => _previewKey = key);
    _player.loadVideoById(videoId: key);
  }

  Future<void> _pinValue(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.updateMovie(widget.movieId, trailerYoutube: v);
      setState(() => _pin = v);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trailer set — re-pulling for all devices')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isPinned(Video v) {
    final pk = _keyOf(_pin);
    return pk != null && pk == v.key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Trailer · ${widget.title}')),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _previewKey == null
                ? const ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('Select a trailer to preview')),
                  )
                : YoutubePlayer(controller: _player),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('TMDB trailers',
                style: theme.textTheme.titleMedium),
          ),
          if (widget.videos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('TMDB has no trailers for this movie — paste a link below.'),
            ),
          for (final v in widget.videos)
            ListTile(
              leading: Icon(
                _isPinned(v) ? Icons.check_circle : Icons.play_circle_outline,
                color: _isPinned(v) ? Colors.amber : null,
              ),
              title: Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                v.type,
                if (v.official) 'Official',
              ].where((s) => s.isNotEmpty).join(' · ')),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _preview(v.key),
                    child: const Text('Preview'),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : () => _pinValue(v.url),
                    child: Text(_isPinned(v) ? 'In use' : 'Use this'),
                  ),
                ],
              ),
              onTap: () => _preview(v.key),
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Or paste a link', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCtrl,
                        decoration: const InputDecoration(
                          hintText: 'https://www.youtube.com/watch?v=…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (s) {
                          final k = _keyOf(s);
                          if (k != null && k.isNotEmpty) _preview(k);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          _saving ? null : () => _pinValue(_manualCtrl.text),
                      child: const Text('Pin'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
