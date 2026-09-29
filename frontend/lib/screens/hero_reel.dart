// The fullscreen hero reel's native player (Windows). Conditional export keeps
// dart:ffi (the embed window) out of the web bundle — b43 broke on exactly
// that. Everywhere else the stub reports unsupported and the hero keeps its
// texture player.
export 'hero_reel_stub.dart' if (dart.library.io) 'hero_reel_native.dart';
