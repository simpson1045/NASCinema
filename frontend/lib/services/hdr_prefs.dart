import 'package:shared_preferences/shared_preferences.dart';

import 'display_hdr.dart';

/// "HDR trailers": Auto (use HDR when this device's display has HDR on),
/// Always, or Never. Per device. HDR trailers play in the native player, the
/// only path that shows HDR properly; the hero behind the menus stays SDR.
enum HdrMode { auto, always, never }

const kHdrTrailersPref = 'hdr_trailers';

class HdrPrefs {
  HdrPrefs._();

  static bool? _detected;
  static DateTime _detectedAt = DateTime(0);

  static Future<HdrMode> mode() async {
    final p = await SharedPreferences.getInstance();
    return HdrMode.values.asNameMap()[p.getString(kHdrTrailersPref)] ??
        HdrMode.auto;
  }

  static Future<void> setMode(HdrMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kHdrTrailersPref, m.name);
  }

  /// Should trailers play in HDR right now? Detection is cached for a minute
  /// (HDR can be toggled in Windows while the app runs).
  static Future<bool> wantHdr() async {
    switch (await mode()) {
      case HdrMode.always:
        return true;
      case HdrMode.never:
        return false;
      case HdrMode.auto:
        if (_detected == null ||
            DateTime.now().difference(_detectedAt).inSeconds > 60) {
          _detected = await displayHdrActive();
          _detectedAt = DateTime.now();
        }
        return _detected!;
    }
  }
}
