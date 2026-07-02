import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// True only on real desktop targets — window_manager is a no-op elsewhere, so
/// every call below guards on this.
bool get isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;

// Window-state persistence: the app reopens exactly where/how you left it
// instead of launching at the runner's small default every time.
const _kWinX = 'win_x';
const _kWinY = 'win_y';
const _kWinW = 'win_w';
const _kWinH = 'win_h';
const _kWinMax = 'win_max';

/// Must run before runApp on desktop so window_manager can drive the window.
/// Restores the last window bounds/maximized state, then starts tracking.
Future<void> initWindowForDesktop() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final w = prefs.getDouble(_kWinW) ?? 0;
  final h = prefs.getDouble(_kWinH) ?? 0;
  // Sanity floor: never restore a sliver (or garbage from a bad save).
  if (w >= 640 && h >= 480) {
    final x = prefs.getDouble(_kWinX);
    final y = prefs.getDouble(_kWinY);
    // Position only if it plausibly lands on a monitor; a detached display
    // could otherwise strand the window offscreen. Size restore always wins.
    if (x != null && y != null && x > -8000 && x < 16000 && y > -8000 && y < 16000) {
      await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
    } else {
      await windowManager.setSize(Size(w, h));
      await windowManager.center();
    }
  }
  if (prefs.getBool(_kWinMax) ?? false) {
    await windowManager.maximize();
  }

  windowManager.addListener(_WindowStateSaver());
}

/// Toggle borderless fullscreen (hides the title bar + window chrome).
Future<void> toggleFullscreen() async {
  if (!isDesktop) return;
  final full = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!full);
}

/// Saves bounds/maximized on change, debounced so a drag doesn't write a
/// hundred times. Fullscreen (F11) is transient and never saved.
class _WindowStateSaver with WindowListener {
  Timer? _debounce;

  void _queueSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    try {
      if (await windowManager.isFullScreen()) return;
      final prefs = await SharedPreferences.getInstance();
      final maximized = await windowManager.isMaximized();
      await prefs.setBool(_kWinMax, maximized);
      if (!maximized) {
        final b = await windowManager.getBounds();
        await prefs.setDouble(_kWinX, b.left);
        await prefs.setDouble(_kWinY, b.top);
        await prefs.setDouble(_kWinW, b.width);
        await prefs.setDouble(_kWinH, b.height);
      }
    } catch (_) {
      // best-effort — never let state-saving break the app
    }
  }

  @override
  void onWindowResized() => _queueSave();

  @override
  void onWindowMoved() => _queueSave();

  @override
  void onWindowMaximize() => _queueSave();

  @override
  void onWindowUnmaximize() => _queueSave();
}
