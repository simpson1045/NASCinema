import 'package:flutter/material.dart';

/// Native fallback. Desktop/mobile will use media_kit (libmpv) for real
/// direct-play; until then, this is a placeholder.
Widget buildPlayerView(String url, bool isHls) {
  return const Center(
    child: Text(
      'Native playback arrives with the desktop app (media_kit).',
      style: TextStyle(color: Colors.white70),
    ),
  );
}
