import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('nascinemaAttachHls')
external void _attachHls(web.HTMLVideoElement video, String url);

int _counter = 0;

/// Web player: an HTML <video> element. HLS streams are attached via hls.js
/// (the helper in web/index.html); direct files set src directly.
Widget buildPlayerView(String url, bool isHls) {
  final viewType = 'nascinema-video-${_counter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final video = web.HTMLVideoElement()
      ..controls = true
      ..autoplay = true
      ..muted = true;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = 'black';
    if (isHls) {
      _attachHls(video, url);
    } else {
      video.src = url;
    }
    return video;
  });
  return HtmlElementView(viewType: viewType);
}
