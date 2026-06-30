// Borderless fullscreen for the desktop app. Conditional export keeps
// window_manager out of the web bundle (it has no web implementation): web gets
// the no-op stub, desktop/mobile get the real thing (guarded to desktop at runtime).
export 'fullscreen_stub.dart'
    if (dart.library.io) 'fullscreen_io.dart';
