import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('nascinemaAttachHls')
external void _attachHls(web.HTMLVideoElement video, String url);

int _counter = 0;

/// Web player: an HTML <video>. Playback starts via play() once the source is
/// ready, riding the transient user activation from the detail-screen Play tap,
/// so it runs unmuted with no overlay button.
Widget buildPlayerView(String url, bool isHls) {
  final viewType = 'nascinema-video-${_counter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final video = web.HTMLVideoElement()..controls = true;
    video.style
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('background', 'black');
    if (isHls) {
      _attachHls(video, url);
    } else {
      video.src = url;
      video.play();
    }
    return video;
  });
  return HtmlElementView(viewType: viewType);
}
