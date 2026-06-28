import 'package:flutter/material.dart';

import '../screens/remote_screen.dart';
import 'api_service.dart';
import 'cast_controller.dart';

/// Send a library file to the connected TV and switch the phone to the remote.
///
/// Shared by the movie-detail "Play" banner (cast straight to the TV when a
/// session is already connected) and the in-player cast button. A Chromecast is
/// browser-class, so we always hand it the **web** decision URL (transcoded HLS
/// or a browser-native direct file) — never this device's client URL. Through
/// the custom receiver the media + subtitle URLs must be HTTPS (its page is
/// HTTPS; mixed content is blocked), so we prefix with the cast base.
Future<void> castFileToTv(
  BuildContext context, {
  required CastController cast,
  required String baseUrl,
  required int fileId,
  required String title,
  Object? activeSubtitleId,
}) async {
  final api = ApiService(baseUrl);
  final web = await api.getPlay(fileId, client: 'web');
  final castBase = cast.hasCustomReceiver ? cast.castBase : baseUrl;

  // Which subtitle to start on: an explicit pick (in-player), else the saved
  // resume subtitle.
  final wantSub = activeSubtitleId ?? web.resumeSubtitle;

  // Declare every available subtitle as a cast track (trackId = index + 1) so
  // the remote can switch among them; activeSubId picks the starting one. Each
  // track carries its backend subtitle id (subId) so progress can be saved.
  final subtitleTracks = <Map<String, dynamic>>[];
  var activeSubId = 0;
  try {
    final r = await api.getSubtitles(fileId);
    for (var i = 0; i < r.subtitles.length; i++) {
      final s = r.subtitles[i];
      final u = s['url'];
      if (u == null) continue;
      final id = i + 1;
      subtitleTracks.add({
        'trackId': id,
        'url': '$castBase$u',
        'name': (s['label'] ?? 'Subtitle $id').toString(),
        'language': 'und',
        'subId': s['id'],
      });
      if (wantSub != null && s['id'] == wantSub) {
        activeSubId = id;
      }
    }
  } catch (_) {
    // best-effort — casting works without declared subtitle tracks
  }

  final src = web.source;
  final meta = <String>[
    if (src['height'] != null) '${src['height']}p',
    if (src['hdr'] == true) 'HDR',
    if (src['audio_codec'] != null) src['audio_codec'].toString().toUpperCase(),
  ].join(' · ');

  await cast.castVideo(
    fileId: fileId,
    url: '$castBase${web.url}',
    contentType:
        web.mode == 'direct' ? 'video/mp4' : 'application/vnd.apple.mpegurl',
    title: title,
    source: web.source,
    backdrop: web.backdrop,
    logo: web.logo,
    meta: meta,
    subtitleTracks: subtitleTracks,
    activeSubId: activeSubId,
    startTime: web.resumePosition,
    baseUrl: baseUrl,
  );

  if (!context.mounted) return;
  // Replace the current screen with the remote — disposing any local player so
  // playback doesn't double up.
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => RemoteScreen(baseUrl: baseUrl)),
  );
}
