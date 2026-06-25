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

// Accessors mirrored from the web player; no-ops until media_kit lands.
double playerCurrentTime() => 0;
double playerDuration() => 0;
bool playerPaused() => true;
void playerSeek(double seconds) {}
void playerTogglePlay() {}
List<double> playerBuffered() => const [];
double playerVolume() => 1;
bool playerMuted() => false;
void playerSetVolume(double v) {}
void playerToggleMute() {}
bool playerIsFullscreen() => false;
void playerToggleFullscreen() {}
void installPlayerKeys() {}
void removePlayerKeys() {}
void playerSetSubtitle(String url) {}
void playerClearSubtitle() {}
