import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// What a screen reports about itself when a flag is raised. Read at the
/// moment of the press, so it's always live: which movie, what's playing,
/// where in it. Known keys go to their own columns (kind, movie_id,
/// movie_title, media_file_id, position_seconds); anything else is kept as
/// free-form context.
typedef FlagInfo = Map<String, Object?> Function();

/// Couch-side problem reports. Press the controller's View button (or F8)
/// the moment something looks or sounds wrong: the app grabs a screenshot plus
/// what was on screen and sends it to the server, shows "Flagged", and gets
/// out of the way. Claude reads the open flags each session.
class FlagService {
  FlagService._();

  // Screens register in order; the newest registration still present is the
  // screen on top. Keyed by owner so a screen can update or drop only its own.
  static final Map<Object, (String, FlagInfo?)> _screens = {};
  static String? _baseUrl;
  static bool _busy = false;

  /// Swapped for a fake in tests.
  @visibleForTesting
  static http.Client Function() newClient = http.Client.new;

  /// Root boundary the screenshot is taken from (see [FlagHost]).
  static final GlobalKey boundaryKey = GlobalKey();

  /// Toast text for [FlagHost]; null = hidden.
  static final ValueNotifier<String?> toast = ValueNotifier(null);

  static void register(Object owner, String screen, String baseUrl,
      [FlagInfo? info]) {
    _screens.remove(owner); // re-register moves it to the top
    _screens[owner] = (screen, info);
    _baseUrl = baseUrl;
  }

  static void unregister(Object owner) => _screens.remove(owner);

  static Future<void> flag() async {
    if (_busy) return; // one press, one flag
    final base = _baseUrl;
    if (base == null) {
      _show('Not connected — flag not sent');
      return;
    }
    _busy = true;
    _show('Flagged ✓');
    try {
      final top = _screens.isEmpty ? null : _screens.entries.last.value;
      final info = <String, Object?>{};
      try {
        info.addAll(top?.$2?.call() ?? const {});
      } catch (_) {} // a flag without details beats no flag
      const columns = {
        'kind', 'movie_id', 'movie_title', 'media_file_id', 'position_seconds'
      };
      final pkg = await PackageInfo.fromPlatform();
      final body = <String, Object?>{
        'app_version': '${pkg.version}+${pkg.buildNumber}',
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'screen': top?.$1,
        for (final k in columns)
          if (info[k] != null) k: info[k],
        'context': {
          for (final e in info.entries)
            if (!columns.contains(e.key)) e.key: e.value?.toString(),
          'screens': [for (final s in _screens.values) s.$1],
        },
        'screenshot_png_b64': await _screenshot(),
      };
      final client = newClient();
      final r = await client
          .post(
            Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/flags'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20))
          .whenComplete(client.close);
      if (r.statusCode != 200) _show('Flag failed (${r.statusCode})');
    } catch (_) {
      _show('Flag failed — server unreachable');
    } finally {
      _busy = false;
    }
  }

  /// The app window as PNG, at most 1080 lines tall. The mpv movie picture is
  /// a separate native window and won't be in it — the timestamp covers that.
  static Future<String?> _screenshot() async {
    try {
      final b = boundaryKey.currentContext?.findRenderObject();
      if (b is! RenderRepaintBoundary || b.size.height <= 0) return null;
      final ratio = 1080 / b.size.height;
      final image = await b.toImage(pixelRatio: ratio > 2 ? 2 : ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png == null ? null : base64Encode(png.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Timer? _toastTimer;
  static void _show(String text) {
    toast.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () => toast.value = null);
  }
}
