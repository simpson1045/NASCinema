import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// True only on real desktop targets — window_manager is a no-op elsewhere, so
/// every call below guards on this.
bool get isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Must run before runApp on desktop so window_manager can drive the window.
Future<void> initWindowForDesktop() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
}

/// Toggle borderless fullscreen (hides the title bar + window chrome).
Future<void> toggleFullscreen() async {
  if (!isDesktop) return;
  final full = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!full);
}
