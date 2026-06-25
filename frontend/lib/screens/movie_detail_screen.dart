import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/extra.dart';
import '../models/movie.dart';
import '../models/movie_file.dart';
import '../models/video.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';

const _extraTypes = <String>[
  'Featurette', 'Trailer', 'Deleted Scene', 'Behind the Scenes', 'Interview',
  'Documentary', 'Music Video', 'Blooper', 'Short', 'Special', 'Extra',
];

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({
    super.key,
    required this.movie,
    required this.baseUrl,
  });

  final Movie movie;
  final String baseUrl;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  List<MovieFile> _files = const [];
  List<Extra> _extras = const [];
  List<Video> _videos = const [];
  bool _loading = true;
  String? _error;
  String? _blurayUrl;

  @override
  void initState() {
    super.initState();
    _blurayUrl = widget.movie.blurayUrl;
    _load();
  }

  Future<void> _load() async {
    try {
      final detailF = _api.getMovieDetail(widget.movie.id);
      final videos =
          await _api.getMovieVideos(widget.movie.id).catchError((_) => <Video>[]);
      final detail = await detailF;
      if (!mounted) return;
      setState(() {
        _files = detail.files;
        _extras = detail.extras;
        _videos = videos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: NasColors.surfaceRaised,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _editExtra(Extra e) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditExtraDialog(extra: e),
    );
    if (result == null) return;
    final (title, type) = result;
    try {
      await _api.updateExtra(e.id, title: title, type: type);
      setState(() {
        final i = _extras.indexWhere((x) => x.id == e.id);
        if (i >= 0) {
          _extras = List.of(_extras)
            ..[i] = Extra(
              id: e.id,
              title: title,
              type: type,
              resolution: e.resolution,
              duration: e.duration,
              sizeBytes: e.sizeBytes,
            );
        }
      });
    } catch (err) {
      _snack('Could not save: $err');
    }
  }

  Future<void> _openVideo(Video v) async {
    final uri = Uri.tryParse(v.url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open the video');
    }
  }

  void _play() {
    if (_files.isEmpty) {
      _snack('Still loading the file…');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        fileId: _files.first.id,
        baseUrl: widget.baseUrl,
        title: widget.movie.title,
      ),
    ));
  }

  Future<void> _openBluray() async {
    final link = (_blurayUrl != null && _blurayUrl!.isNotEmpty)
        ? _blurayUrl!
        : widget.movie.blurayLink;
    final uri = Uri.tryParse(link);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open Blu-ray.com');
    }
  }

  Future<void> _pinRelease() async {
    final ctrl = TextEditingController(text: _blurayUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NasColors.surface,
        title: const Text('Pin Blu-ray.com release',
            style: TextStyle(color: NasColors.text, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Paste the Blu-ray.com page URL for your exact pressing. Leave blank to clear.',
                style: TextStyle(color: NasColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: NasColors.text),
              decoration: const InputDecoration(
                  hintText: 'https://www.blu-ray.com/movies/...'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: NasColors.muted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (url == null) return;
    try {
      await _api.updateMovie(widget.movie.id, blurayUrl: url.trim());
      setState(() => _blurayUrl = url.trim().isEmpty ? null : url.trim());
      _snack(url.trim().isEmpty ? 'Release link cleared' : 'Release pinned');
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Widget _blurayBar() {
    final pinned = _blurayUrl != null && _blurayUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: NasColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: NasColors.violet.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.album_outlined,
                color: NasColors.violet, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Special features on Blu-ray.com',
                    style: TextStyle(
                        color: NasColors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500)),
                Text(
                    pinned
                        ? 'Pinned release · look up names, then edit below'
                        : 'Search & pin your exact pressing',
                    style: const TextStyle(
                        color: NasColors.muted, fontSize: 11.5)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _openBluray,
            icon: const Icon(Icons.open_in_new,
                size: 16, color: NasColors.amber),
            label: const Text('Open', style: TextStyle(color: NasColors.amber)),
          ),
          IconButton(
            onPressed: _pinRelease,
            icon: const Icon(Icons.link, color: NasColors.muted, size: 18),
            tooltip: pinned ? 'Change release URL' : 'Pin release URL',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Scaffold(
      backgroundColor: NasColors.bg,
      body: Stack(
        children: [
          _AmbientBackdrop(url: movie.backdropUrl()),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(movie: movie)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ActionsRow(onPlay: _play, movie: movie),
                    if (movie.genres.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Genres(genres: movie.genres),
                    ],
                    if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SectionLabel('Overview'),
                      const SizedBox(height: 8),
                      Text(movie.overview!,
                          style: const TextStyle(
                              color: NasColors.text, fontSize: 14.5, height: 1.6)),
                    ],
                    const SizedBox(height: 22),
                    _blurayBar(),
                    const SizedBox(height: 26),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: NasColors.amber))),
                      )
                    else if (_error != null)
                      Text('Could not load details: $_error',
                          style:
                              const TextStyle(color: NasColors.bad, fontSize: 13))
                    else ...[
                      if (_extras.isNotEmpty) ...[
                        _ExtrasSection(
                            extras: _extras,
                            onPlay: () => _snack('Extras playback lands soon 🍿'),
                            onEdit: _editExtra),
                        const SizedBox(height: 28),
                      ],
                      if (_videos.isNotEmpty) ...[
                        _VideosSection(videos: _videos, onTap: _openVideo),
                        const SizedBox(height: 28),
                      ],
                      const _SectionLabel('Files'),
                      const SizedBox(height: 10),
                      for (final f in _files) _FileCard(file: f),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: Image.network(url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: NasColors.bg)),
          ),
          const ColoredBox(color: Color(0xD90A0E27)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final backdrop = movie.backdropUrl();
    final chips = <String>[
      if (movie.qualityBadge != null) movie.qualityBadge!,
      if (movie.videoCodec != null) movie.videoCodec!.toUpperCase(),
    ];
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null)
            Image.network(backdrop, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0xCC0A0E27), NasColors.bg],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: NasColors.text),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 108,
                    height: 162,
                    child: movie.posterUrl(size: 'w342') != null
                        ? Image.network(movie.posterUrl(size: 'w342')!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                                color: NasColors.surfaceRaised))
                        : const ColoredBox(color: NasColors.surfaceRaised),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(movie.title,
                          style: const TextStyle(
                              color: NasColors.text,
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              height: 1.15)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (movie.rating != null) ...[
                            const Icon(Icons.star_rounded,
                                color: NasColors.amber, size: 17),
                            const SizedBox(width: 3),
                            Text(movie.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: NasColors.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              [
                                if (movie.year != null) '${movie.year}',
                                if (movie.runtimeLabel != null)
                                  movie.runtimeLabel!,
                              ].join('  ·  '),
                              style: const TextStyle(
                                  color: NasColors.muted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in chips) _Chip(c, NasColors.amber),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.onPlay, required this.movie});
  final VoidCallback onPlay;
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: const Text('Play',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        if (movie.fileCount > 1) ...[
          const SizedBox(width: 10),
          _Chip('${movie.fileCount} versions', NasColors.violet, big: true),
        ],
      ],
    );
  }
}

class _ExtrasSection extends StatelessWidget {
  const _ExtrasSection({
    required this.extras,
    required this.onPlay,
    required this.onEdit,
  });
  final List<Extra> extras;
  final VoidCallback onPlay;
  final void Function(Extra) onEdit;

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<Extra>>{};
    for (final e in extras) {
      (byType[e.type] ??= []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Bonus features'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: NasColors.amber,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${extras.length}',
                  style: const TextStyle(
                      color: NasColors.bg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final entry in byType.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text('${entry.key}  ·  ${entry.value.length}',
                style: const TextStyle(
                    color: NasColors.violet,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          for (final e in entry.value)
            _ExtraRow(extra: e, onPlay: onPlay, onEdit: () => onEdit(e)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.extra,
    required this.onPlay,
    required this.onEdit,
  });
  final Extra extra;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: NasColors.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onPlay,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: NasColors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: NasColors.amber, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(extra.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NasColors.text, fontSize: 13.5)),
                    ),
                    if (extra.durationLabel != null) ...[
                      const SizedBox(width: 10),
                      Text(extra.durationLabel!,
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined,
                color: NasColors.muted, size: 18),
            tooltip: 'Rename / retype',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _VideosSection extends StatelessWidget {
  const _VideosSection({required this.videos, required this.onTap});
  final List<Video> videos;
  final void Function(Video) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Trailers & clips'),
            const SizedBox(width: 8),
            const Text('from TMDB · opens YouTube',
                style: TextStyle(color: NasColors.muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 12),
        for (final v in videos)
          InkWell(
            onTap: () => onTap(v),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: NasColors.surface,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: NasColors.violet.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.smart_display_outlined,
                        color: NasColors.violet, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(v.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: NasColors.text, fontSize: 13.5)),
                  ),
                  if (v.type.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _Chip(v.type, NasColors.muted),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new,
                      color: NasColors.muted, size: 16),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Genres extends StatelessWidget {
  const _Genres({required this.genres});
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: NasColors.surface,
                borderRadius: BorderRadius.circular(20)),
            child: Text(g,
                style: const TextStyle(color: NasColors.muted, fontSize: 12)),
          ),
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});
  final MovieFile file;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      if (file.container != null) file.container!.toUpperCase(),
      file.resolution,
      if (file.videoCodec != null) file.videoCodec!,
      if (file.audioCodec != null) file.audioCodec!,
      if (file.bitDepth != null) '${file.bitDepth}-bit',
      if (file.hdr) 'HDR',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: NasColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: NasColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final b in badges) _Chip(b, NasColors.muted)],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (file.durationLabel != null) file.durationLabel!,
              file.sizeLabel,
            ].join('  ·  '),
            style: const TextStyle(color: NasColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color, {this.big = false});
  final String text;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: big ? 12 : 8, vertical: big ? 8 : 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(big ? 10 : 6)),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: big ? 13 : 11,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: NasColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1));
  }
}

class _EditExtraDialog extends StatefulWidget {
  const _EditExtraDialog({required this.extra});
  final Extra extra;

  @override
  State<_EditExtraDialog> createState() => _EditExtraDialogState();
}

class _EditExtraDialogState extends State<_EditExtraDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.extra.title);
  late String _type = _extraTypes.contains(widget.extra.type)
      ? widget.extra.type
      : 'Extra';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NasColors.surface,
      title: const Text('Edit bonus feature',
          style: TextStyle(color: NasColors.text, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            style: const TextStyle(color: NasColors.text),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _type,
            dropdownColor: NasColors.surfaceRaised,
            style: const TextStyle(color: NasColors.text),
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in _extraTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: NasColors.muted)),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop((_title.text.trim(), _type)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
