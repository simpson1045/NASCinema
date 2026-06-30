import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/video.dart';
import '../services/api_service.dart';

/// Pick which trailer a movie uses on every device (Roku included). Shows TMDB's
/// trailers AND a manual-URL field up front; preview opens on demand. Saving
/// writes the backend's `trailer_youtube` override.
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
  final _manualCtrl = TextEditingController();
  String? _pin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pin = widget.currentPin;
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  String? _keyOf(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;
    if (s.contains('watch?v=')) return s.split('watch?v=')[1].split('&')[0];
    if (s.contains('youtu.be/')) return s.split('youtu.be/')[1].split('?')[0];
    if (s.contains('/')) return s.split('/').last.split('?')[0];
    return s;
  }

  bool _isPinned(String url) {
    final pk = _keyOf(_pin);
    final vk = _keyOf(url);
    return pk != null && pk == vk;
  }

  void _preview(String key) {
    if (key.isEmpty) return;
    final controller = YoutubePlayerController.fromVideoId(
      videoId: key,
      autoPlay: true,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: YoutubePlayer(controller: controller),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://www.youtube.com/watch?v=$key'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open on YouTube'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).then((_) => controller.close());
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_pin); // hand the pin back
      },
      child: Scaffold(
      appBar: AppBar(title: Text('Trailer · ${widget.title}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Manual URL — up front, so it's never hidden.
          Text('Paste a trailer link', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Any YouTube (or yt-dlp-supported) URL. Use this when TMDB\'s options '
            'are bad or none preview.',
            style: theme.textTheme.bodySmall,
          ),
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
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  final k = _keyOf(_manualCtrl.text);
                  if (k != null && k.isNotEmpty) _preview(k);
                },
                child: const Text('Preview'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : () => _pinValue(_manualCtrl.text),
                child: const Text('Pin'),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('TMDB trailers (${widget.videos.length})',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (widget.videos.isEmpty)
            Text('TMDB has no trailers for this movie — paste a link above.',
                style: theme.textTheme.bodyMedium),
          for (final v in widget.videos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _isPinned(v.url)
                      ? Icons.check_circle
                      : Icons.play_circle_outline,
                  color: _isPinned(v.url) ? Colors.amber : null,
                ),
                title: Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  if (v.type.isNotEmpty) v.type,
                  if (v.official) 'Official',
                ].join(' · ')),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: () => _preview(v.key),
                      child: const Text('Preview'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : () => _pinValue(v.url),
                      child: Text(_isPinned(v.url) ? 'In use' : 'Use'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
