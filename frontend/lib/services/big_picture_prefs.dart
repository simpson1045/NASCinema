import 'package:shared_preferences/shared_preferences.dart';

import 'fullscreen.dart';

/// "Start in Big Picture": the Windows renderer boots straight into the
/// fullscreen 10-foot UI. On by default there — it's the couch PC — and never
/// on phones/web, where the big picture layout makes no sense.
const kBigPicturePref = 'big_picture_start';

bool get bigPictureAvailable => isDesktop;

Future<bool> startInBigPicture() async {
  if (!bigPictureAvailable) return false;
  final p = await SharedPreferences.getInstance();
  return p.getBool(kBigPicturePref) ?? true;
}
