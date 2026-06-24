import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../models/movie_file.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
  late final Future<List<MovieFile>> _files =
      ApiService(widget.baseUrl).getMovieFiles(widget.movie.id);

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playback lands in the next milestone 🍿'),
        backgroundColor: NasColors.surfaceRaised,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(movie: movie)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _MetaRow(movie: movie),
                const SizedBox(height: 16),
                if (movie.genres.isNotEmpty) _Genres(genres: movie.genres),
                if (movie.genres.isNotEmpty) const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _comingSoon,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
                if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _SectionLabel('Overview'),
                  const SizedBox(height: 8),
                  Text(
                    movie.overview!,
                    style: const TextStyle(
                      color: NasColors.text,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const _SectionLabel('Files'),
                const SizedBox(height: 8),
                _FilesSection(future: _files),
              ]),
            ),
          ),
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
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null)
            Image.network(backdrop, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox())
          else
            const SizedBox(),
          // Fade the backdrop into the page background.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x880A0E27),
                  Color(0xCC0A0E27),
                  NasColors.bg,
                ],
                stops: [0.0, 0.55, 1.0],
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
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 150,
                    child: movie.posterUrl(size: 'w342') != null
                        ? Image.network(movie.posterUrl(size: 'w342')!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                                color: NasColors.surfaceRaised))
                        : const ColoredBox(color: NasColors.surfaceRaised),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        movie.title,
                        style: const TextStyle(
                          color: NasColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (movie.year != null) '${movie.year}',
                          if (movie.runtimeLabel != null) movie.runtimeLabel!,
                        ].join('  ·  '),
                        style: const TextStyle(
                            color: NasColors.muted, fontSize: 13),
                      ),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (movie.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: NasColors.amber, size: 18),
              const SizedBox(width: 4),
              Text(movie.rating!.toStringAsFixed(1),
                  style: const TextStyle(
                      color: NasColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        if (movie.fileCount > 1)
          _Pill('${movie.fileCount} versions', NasColors.violet),
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(g,
                style: const TextStyle(color: NasColors.muted, fontSize: 12)),
          ),
      ],
    );
  }
}

class _FilesSection extends StatelessWidget {
  const _FilesSection({required this.future});
  final Future<List<MovieFile>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MovieFile>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: NasColors.amber))),
          );
        }
        if (snap.hasError) {
          return Text('Could not load files: ${snap.error}',
              style: const TextStyle(color: NasColors.bad, fontSize: 13));
        }
        final files = snap.data ?? const [];
        return Column(
          children: [for (final f in files) _FileCard(file: f)],
        );
      },
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
        color: NasColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
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
            children: [for (final b in badges) _Pill(b, NasColors.muted)],
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

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w500)),
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
