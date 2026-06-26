import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cast_controller.dart';
import '../theme/app_theme.dart';
import 'player/scrubber.dart';

/// "Phone as remote": once a movie is casting, this drives the TV — play/pause,
/// scrub, stop — bound to the app-level [CastController]. Backing out returns to
/// the library WITHOUT dropping the cast (the controller lives above the nav),
/// and the library's now-casting bar reopens this.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key, required this.baseUrl});

  final String baseUrl;

  String _fmt(Duration d) {
    final t = d.inSeconds;
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cast = context.watch<CastController>();

    // Cast ended (stopped, or the TV killed it) — leave the remote.
    if (!cast.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white),
                  tooltip: 'Back to library',
                ),
                const Expanded(
                  child: Text('Casting',
                      style: TextStyle(
                          color: NasColors.muted,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: NasColors.amber.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cast_connected,
                          color: NasColors.amber, size: 44),
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        cast.castingTitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('on ${cast.connectedDevice?.name ?? 'TV'}',
                        style: const TextStyle(
                            color: NasColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_fmt(cast.position),
                      style: const TextStyle(
                          color: NasColors.muted, fontSize: 12)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Scrubber(
                      duration: cast.duration.inMilliseconds / 1000,
                      position: cast.position.inMilliseconds / 1000,
                      buffered: const [],
                      cached: const [],
                      onSeek: cast.seekTo,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_fmt(cast.duration),
                      style: const TextStyle(
                          color: NasColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  onPressed: () =>
                      cast.seekTo((cast.position.inSeconds - 10).toDouble()),
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 64,
                  onPressed: () => cast.isPlaying ? cast.pause() : cast.play(),
                  icon: Icon(
                      cast.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: NasColors.amber),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed: () =>
                      cast.seekTo((cast.position.inSeconds + 10).toDouble()),
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => cast.disconnect(),
              icon: const Icon(Icons.stop_circle_outlined,
                  color: NasColors.muted, size: 18),
              label: const Text('Stop casting',
                  style: TextStyle(color: NasColors.muted)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
