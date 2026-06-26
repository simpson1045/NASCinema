import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cast_controller.dart';
import '../theme/app_theme.dart';

/// "Phone as remote" — a Roku/Firestick-style remote for the cast session: a
/// D-pad ring (center play/pause, ←→ seek, ↑↓ volume) over a button cluster
/// (subtitles, audio, chapters, speed, library, stop). Bound to the app-level
/// [CastController]; backing out keeps the cast alive (the now-casting bar
/// reopens this).
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

  void _toLibrary(BuildContext context) => Navigator.of(context)
      .popUntil((r) => r.settings.name == 'library' || r.isFirst);

  void _soon(BuildContext context, String what) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: NasColors.surface,
        duration: const Duration(seconds: 2),
        content: Text('$what — coming soon',
            style: const TextStyle(color: NasColors.text)),
      ));

  @override
  Widget build(BuildContext context) {
    final cast = context.watch<CastController>();

    if (!cast.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _toLibrary(context),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white),
                        tooltip: 'Back to library',
                      ),
                      Expanded(
                        child: Text(cast.connectedDevice?.name ?? 'TV',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: NasColors.muted, fontSize: 12)),
                      ),
                      const Icon(Icons.cast_connected,
                          color: NasColors.amber, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(cast.castingTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(_fmt(cast.position),
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 11)),
                      Expanded(child: _scrubber(cast)),
                      Text(_fmt(cast.duration),
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _dpad(cast),
                  const SizedBox(height: 22),
                  _buttonGrid(context, cast),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrubber(CastController cast) {
    final dur = cast.duration.inMilliseconds.toDouble();
    final pos = cast.position.inMilliseconds.toDouble().clamp(0.0, dur);
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            if (dur <= 0) return;
            cast.seekTo((d.localPosition.dx / c.maxWidth) * dur / 1000);
          },
          child: SizedBox(
            height: 18,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: NasColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(2))),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                          color: NasColors.amber,
                          borderRadius: BorderRadius.circular(2))),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _dpad(CastController cast) {
    final vol = cast.volumeControllable;
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: NasColors.surfaceRaised, width: 1.5),
            ),
          ),
          if (vol)
            Align(
              alignment: Alignment.topCenter,
              child: _ring(Icons.volume_up_rounded,
                  () => cast.adjustVolume(0.1), 'Volume up'),
            ),
          if (vol)
            Align(
              alignment: Alignment.bottomCenter,
              child: _ring(Icons.volume_down_rounded,
                  () => cast.adjustVolume(-0.1), 'Volume down'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: _ring(Icons.replay_10,
                () => cast.seekTo(cast.position.inSeconds - 10.0), 'Back 10s'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _ring(Icons.forward_10,
                () => cast.seekTo(cast.position.inSeconds + 10.0), 'Forward 10s'),
          ),
          GestureDetector(
            onTap: () => cast.isPlaying ? cast.pause() : cast.play(),
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: NasColors.amber),
              child: Icon(
                  cast.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(IconData icon, VoidCallback onTap, String label) => IconButton(
        onPressed: onTap,
        tooltip: label,
        icon: Icon(icon, color: Colors.white, size: 24),
      );

  Widget _buttonGrid(BuildContext context, CastController cast) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(
                icon: Icons.closed_caption,
                label: 'Subtitles',
                active: cast.subtitlesOn,
                enabled: cast.hasSubtitles,
                onTap: cast.toggleSubtitles),
            _round(
                icon: Icons.headphones,
                label: 'Audio',
                onTap: () => _soon(context, 'Audio track')),
            _round(
                icon: Icons.format_list_numbered,
                label: 'Chapters',
                onTap: () => _soon(context, 'Chapters')),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(
                icon: Icons.speed,
                label: 'Speed',
                onTap: () => _soon(context, 'Playback speed')),
            _round(
                icon: Icons.grid_view_rounded,
                label: 'Library',
                onTap: () => _toLibrary(context)),
            _round(
                icon: Icons.stop_rounded,
                label: 'Stop',
                danger: true,
                onTap: cast.disconnect),
          ],
        ),
      ],
    );
  }

  Widget _round({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool enabled = true,
    bool danger = false,
  }) {
    final color = !enabled
        ? NasColors.surfaceRaised
        : active
            ? NasColors.amber
            : danger
                ? NasColors.bad
                : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: enabled ? onTap : null,
          radius: 30,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NasColors.surface,
              border: Border.all(color: NasColors.surfaceRaised),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(color: NasColors.muted, fontSize: 10)),
      ],
    );
  }
}
