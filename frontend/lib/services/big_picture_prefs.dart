import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'fullscreen.dart';

/// "Start in Big Picture": the Windows renderer boots straight into the
/// fullscreen 10-foot UI. On by default there — it's the couch PC — and never
/// on phones/web, where the big picture layout makes no sense.
const kBigPicturePref = 'big_picture_start';

bool get bigPictureAvailable => isDesktop || bigPictureWebPreview;

/// `?bp=1` on the web build opens big picture in a browser — a development
/// preview (no trailers on web; layout + keyboard are identical), so changes
/// can be checked without taking over the TV.
bool get bigPictureWebPreview =>
    kIsWeb && Uri.base.queryParameters['bp'] == '1';

Future<bool> startInBigPicture() async {
  if (bigPictureWebPreview) return true;
  if (!bigPictureAvailable) return false;
  final p = await SharedPreferences.getInstance();
  return p.getBool(kBigPicturePref) ?? true;
}
