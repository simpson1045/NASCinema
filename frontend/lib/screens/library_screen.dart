import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  late Future<List<Movie>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listMovies();
  }

  Future<void> _refresh() async {
    setState(() => _future = _api.listMovies());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const Icon(Icons.movie_outlined, color: NasColors.amber, size: 22),
            const SizedBox(width: 8),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: NasColors.text,
                ),
                children: [
                  TextSpan(text: 'NAS'),
                  TextSpan(
                    text: 'Cinema',
                    style: TextStyle(color: NasColors.amber),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: NasColors.muted),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Movie>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: NasColors.amber),
            );
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.error_outline,
              color: NasColors.bad,
              text: 'Could not load library:\n${snap.error}',
            );
          }
          final movies = snap.data ?? const [];
          if (movies.isEmpty) {
            return const _Message(
              icon: Icons.local_movies_outlined,
              color: NasColors.muted,
              text: 'No movies yet — run a library scan on the server.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            color: NasColors.amber,
            backgroundColor: NasColors.surface,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                childAspectRatio: 0.52,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              itemCount: movies.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MovieDetailScreen(
                      movie: movies[i],
                      baseUrl: widget.baseUrl,
                    ),
                  ),
                ),
                child: _PosterCard(movie: movies[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final badge = movie.qualityBadge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Poster(movie: movie),
                if (badge != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NasColors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: NasColors.bg,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: NasColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          [
            if (movie.year != null) '${movie.year}',
            if (movie.rating != null) '★ ${movie.rating!.toStringAsFixed(1)}',
          ].join('  ·  '),
          style: const TextStyle(color: NasColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final url = movie.posterUrl();
    if (url == null) return const _PosterFallback();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PosterFallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PosterFallback(loading: true),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NasColors.surfaceRaised,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NasColors.muted,
              ),
            )
          : const Icon(Icons.movie_outlined, color: NasColors.muted, size: 28),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NasColors.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
