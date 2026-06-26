import 'package:flutter/foundation.dart';

/// Minimal logger shim. NASRadio's cast/ protocol files (copied verbatim) log
/// through `AppLogger.instance`; this gives them that surface without pulling
/// in NASRadio's file-backed logger. Routes to debugPrint (stripped in release).
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  void info(String message) => debugPrint(message);
  void warning(String message) => debugPrint(message);
  void error(String message) => debugPrint(message);
}
