import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home.dart';
import '../services/api_service.dart';
import '../services/cast_controller.dart';
import '../services/fullscreen.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'cast_picker.dart';
import 'home_widgets.dart';
import 'remote_screen.dart';
import 'search_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  late Future<HomeData> _future;
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    _future = _api.getHome();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _refresh() async {
    // Re-scan the disk (add new files + prune deleted ones), then reload — so
    // Refresh actually reflects the library on disk, not just a DB re-read.
    await _api.triggerScan();
    setState(() => _future = _api.getHome());
    await _future;
  }

  // Connect from the home screen; the movie you open next casts to this device.
  void _openCast(CastController cast) => showModalBottomSheet(
        context: context,
        backgroundColor: NasColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (_) => CastPicker(
          cast: cast,
          onPick: (d) {
            Navigator.pop(context);
            cast.connect(d);
          },
          onDisconnect: () {
            cast.disconnect();
            Navigator.pop(context);
          },
        ),
      );

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate(widget.baseUrl);
    // A persistent banner on the library — not a SnackBar, which fires whenever
    // the async check lands (often after you've opened a movie) and shows up on
    // whatever screen is current.
    if (mounted && info != null) setState(() => _update = info);
  }

  Widget _updateBanner() {
    final u = _update!;
    return Material(
      color: NasColors.amber.withValues(alpha: 0.14),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _UpdateDialog(baseUrl: widget.baseUrl, info: u),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            children: [
              const Icon(Icons.system_update, color: NasColors.amber, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Update available — v${u.version}',
                    style: const TextStyle(
                        color: NasColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              const Text('Update',
                  style: TextStyle(
                      color: NasColors.amber, fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: () => setState(() => _update = null),
                icon: const Icon(Icons.close, color: NasColors.muted, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchScreen(baseUrl: widget.baseUrl),
            )),
            tooltip: 'Search',
            icon: const Icon(Icons.search, color: NasColors.muted),
          ),
          if (isDesktop)
            IconButton(
              onPressed: toggleFullscreen,
              tooltip: 'Fullscreen (F11)',
              icon: const Icon(Icons.fullscreen, color: NasColors.muted),
            ),
          // Connect to the TV from here, then pick a movie. Consumer so only
          // the button repaints on cast updates, not the whole grid.
          Consumer<CastController>(
            builder: (_, cast, _) => cast.supported
                ? IconButton(
                    onPressed: () => _openCast(cast),
                    tooltip: 'Cast to TV',
                    icon: Icon(
                        cast.isConnected ? Icons.cast_connected : Icons.cast,
                        color: cast.isConnected
                            ? NasColors.amber
                            : NasColors.muted),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: NasColors.muted),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_update != null) _updateBanner(),
          Expanded(
            child: FutureBuilder<HomeData>(
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
                final data = snap.data;
                final empty = data == null ||
                    (data.featured.isEmpty &&
                        data.rails.every((r) => r.movies.isEmpty));
                if (empty) {
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
                  child: HomeView(data: data, baseUrl: widget.baseUrl),
                );
              },
            ),
          ),
        ],
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
