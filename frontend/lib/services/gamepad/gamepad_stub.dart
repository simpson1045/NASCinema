import 'pad_button.dart';

export 'pad_button.dart';

/// No controller support on this platform.
class Gamepad {
  Gamepad._();
  static final instance = Gamepad._();

  Stream<PadButton> get presses => const Stream.empty();

  Stream<double> get scroll => const Stream.empty();

  void start() {}
}
