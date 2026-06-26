// Cast seam: native (dart:io socket stack) gets the real CASTV2 sender; web
// falls back to a no-op stub (the browser can't open raw TLS sockets).
export 'cast_controller_stub.dart'
    if (dart.library.io) 'cast_controller_native.dart';
