import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/movie.dart';
import '../services/api_service.dart';
import '../services/cast_controller.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_screen.dart';
import 'remote_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _refresh() async {
    setState(() => _future = _api.listMovies());
    await _future;
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate(widget.baseUrl);
    if (!mounted || info == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: NasColors.surface,
      duration: const Duration(seconds: 8),
      content: Text('Update available — v${info.version}',
          style: const TextStyle(color: NasColors.text)),
      action: SnackBarAction(
        label: 'Update',
        textColor: NasColors.amber,
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _UpdateDialog(baseUrl: widget.baseUrl, info: info),
        ),
      ),
    ));
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
      bottomNavigationBar: _NowCastingBar(baseUrl: widget.baseUrl),
    );
  }
}

/// Persistent bar shown while a cast session is live, so you can browse the
/// library and still see/return to what's playing on the TV.
class _NowCastingBar extends StatelessWidget {
  const _NowCastingBar({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final cast = context.watch<CastController>();
    if (!cast.isConnected) return const SizedBox.shrink();
    return Material(
      color: NasColors.surface,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RemoteScreen(baseUrl: baseUrl)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                const Icon(Icons.cast_connected,
                    color: NasColors.amber, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cast.castingTitle.isEmpty ? 'Casting' : cast.castingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: NasColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      Text('on ${cast.connectedDevice?.name ?? 'TV'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => cast.isPlaying ? cast.pause() : cast.play(),
                  icon: Icon(cast.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white),
                ),
                IconButton(
                  onPressed: () => cast.disconnect(),
                  icon: const Icon(Icons.stop, color: NasColors.muted),
                ),
              ],
            ),
          ),
        ),
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

/// Update prompt: shows the changelog + size, downloads with progress, installs.
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.baseUrl, required this.info});

  final String baseUrl;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await UpdateService.downloadUpdate(
        widget.baseUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await UpdateService.applyUpdate(path);
      // Android: the system installer takes over (we stay). Windows: exits.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Update failed: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mb = widget.info.sizeBytes / 1024 / 1024;
    return AlertDialog(
      backgroundColor: NasColors.surface,
      title: Text('Update to v${widget.info.version}',
          style: const TextStyle(color: NasColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.info.changelog.isNotEmpty)
              Text(widget.info.changelog,
                  style:
                      const TextStyle(color: NasColors.muted, fontSize: 13)),
            if (mb > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Download size: ${mb.toStringAsFixed(1)} MB',
                    style:
                        const TextStyle(color: NasColors.muted, fontSize: 12)),
              ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                        value: _progress,
                        color: NasColors.amber,
                        backgroundColor: NasColors.surfaceRaised),
                    const SizedBox(height: 6),
                    Text('${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: NasColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: NasColors.bad, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Later', style: TextStyle(color: NasColors.muted)),
        ),
        TextButton(
          onPressed: _busy ? null : _start,
          child: Text(_busy ? 'Downloading…' : 'Download & install',
              style: const TextStyle(color: NasColors.amber)),
        ),
      ],
    );
  }
}
