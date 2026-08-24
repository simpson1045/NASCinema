// The featured hero's inline trailer player. Conditional export keeps
// media_kit out of the web bundle (the browser home stays backdrop-only);
// native (Windows renderer + phone) gets the real in-texture player.
export 'hero_trailer_stub.dart'
    if (dart.library.io) 'hero_trailer_native.dart';
