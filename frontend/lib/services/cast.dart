// Chromecast sender seam. Web → real CAF sender (cast_web.dart); everything
// else → no-op stub. Mirrors the player_view conditional-import pattern.
export 'cast_stub.dart' if (dart.library.js_interop) 'cast_web.dart';
