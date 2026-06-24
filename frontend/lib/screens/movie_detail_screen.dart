import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/extra.dart';
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
  late final Future<({List<MovieFile> files, List<Extra> extras})> _detail =
      ApiService(widget.baseUrl).getMovieDetail(widget.movie.id);

  void _comingSoon([String what = 'Playback']) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$what lands in the next milestone 🍿'),
        backgroundColor: NasColors.surfaceRaised,
        duration: const Duration(seconds: 2),
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
                    _ActionsRow(onPlay: () => _comingSoon(), movie: movie),
                    if (movie.genres.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Genres(genres: movie.genres),
                    ],
                    if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SectionLabel('Overview'),
                      const SizedBox(height: 8),
                      Text(
                        movie.overview!,
                        style: const TextStyle(
                          color: NasColors.text,
                          fontSize: 14.5,
                          height: 1.6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _DetailBody(
                      future: _detail,
                      onPlayExtra: () => _comingSoon('Extras playback'),
                    ),
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

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.future, required this.onPlayExtra});
  final Future<({List<MovieFile> files, List<Extra> extras})> future;
  final VoidCallback onPlayExtra;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<MovieFile> files, List<Extra> extras})>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: NasColors.amber))),
          );
        }
        if (snap.hasError) {
          return Text('Could not load details: ${snap.error}',
              style: const TextStyle(color: NasColors.bad, fontSize: 13));
        }
        final files = snap.data?.files ?? const [];
        final extras = snap.data?.extras ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (extras.isNotEmpty) ...[
              _ExtrasSection(extras: extras, onPlay: onPlayExtra),
              const SizedBox(height: 28),
            ],
            const _SectionLabel('Files'),
            const SizedBox(height: 10),
            for (final f in files) _FileCard(file: f),
          ],
        );
      },
    );
  }
}

class _ExtrasSection extends StatelessWidget {
  const _ExtrasSection({required this.extras, required this.onPlay});
  final List<Extra> extras;
  final VoidCallback onPlay;

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
                borderRadius: BorderRadius.circular(20),
              ),
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
            child: Text(
              '${entry.key}  ·  ${entry.value.length}',
              style: const TextStyle(
                  color: NasColors.violet,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          for (final e in entry.value) _ExtraRow(extra: e, onPlay: onPlay),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({required this.extra, required this.onPlay});
  final Extra extra;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NasColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
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
                  style:
                      const TextStyle(color: NasColors.muted, fontSize: 12)),
            ],
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(big ? 10 : 6),
      ),
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
