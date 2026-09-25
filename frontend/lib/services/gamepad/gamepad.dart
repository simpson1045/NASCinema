// Game controller input. XInput (Xbox pads) on Windows; a silent stub
// everywhere else (web has no dart:ffi, phones use touch).
export 'gamepad_stub.dart' if (dart.library.io) 'gamepad_windows.dart';
