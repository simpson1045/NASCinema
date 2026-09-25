/// Xbox controller input on Windows via XInput — hand-rolled FFI like the mpv
/// pipe (no `win32` package). Polled at ~60 Hz on the UI isolate; one
/// XInputGetState call is microseconds.
///
/// XInput stalls when asked about an EMPTY slot, so only the connected slot is
/// polled every tick; the others are re-scanned every 2 s to notice a pad
/// being turned on.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'pad_button.dart';

export 'pad_button.dart';

typedef _GetStateC = Uint32 Function(Uint32 userIndex, Pointer<Uint8> state);
typedef _GetStateDart = int Function(int userIndex, Pointer<Uint8> state);

// XINPUT_GAMEPAD wButtons bits.
const _dpadUp = 0x0001, _dpadDown = 0x0002, _dpadLeft = 0x0004;
const _dpadRight = 0x0008, _start = 0x0010, _back = 0x0020;
const _lb = 0x0100, _rb = 0x0200;
const _a = 0x1000, _b = 0x2000, _x = 0x4000, _y = 0x8000;

const _stickDeadzone = 16000; // of ±32767 — firm push, not a resting drift
const _repeatDelay = Duration(milliseconds: 400);
const _repeatEvery = Duration(milliseconds: 110);

class Gamepad {
  Gamepad._();
  static final instance = Gamepad._();

  final _controller = StreamController<PadButton>.broadcast();
  Stream<PadButton> get presses => _controller.stream;

  _GetStateDart? _getState;
  Pointer<Uint8>? _state;
  Timer? _poll;
  int? _slot;
  DateTime _nextScan = DateTime.fromMillisecondsSinceEpoch(0);
  Set<PadButton> _held = {};
  final Map<PadButton, DateTime> _nextRepeat = {};

  void start() {
    if (!Platform.isWindows || _poll != null) return;
    for (final dll in ['xinput1_4.dll', 'xinput9_1_0.dll']) {
      try {
        _getState = DynamicLibrary.open(dll)
            .lookupFunction<_GetStateC, _GetStateDart>('XInputGetState');
        break;
      } catch (_) {
        // try the next XInput version
      }
    }
    if (_getState == null) return; // no XInput on this machine
    _state = calloc<Uint8>(16); // XINPUT_STATE is 16 bytes
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    final get = _getState!, st = _state!;
    final now = DateTime.now();
    if (_slot == null) {
      if (now.isBefore(_nextScan)) return;
      _nextScan = now.add(const Duration(seconds: 2));
      for (var i = 0; i < 4; i++) {
        if (get(i, st) == 0) {
          _slot = i;
          break;
        }
      }
      if (_slot == null) return;
    }
    if (get(_slot!, st) != 0) {
      _slot = null; // pad turned off / unplugged
      _held = {};
      return;
    }
    final bytes = st.asTypedList(16);
    final buttons = bytes[4] | (bytes[5] << 8);
    int s16(int lo) {
      final v = bytes[lo] | (bytes[lo + 1] << 8);
      return v >= 0x8000 ? v - 0x10000 : v;
    }
    final lx = s16(8), ly = s16(10);

    final down = <PadButton>{
      if (buttons & _dpadUp != 0 || ly > _stickDeadzone) PadButton.up,
      if (buttons & _dpadDown != 0 || ly < -_stickDeadzone) PadButton.down,
      if (buttons & _dpadLeft != 0 || lx < -_stickDeadzone) PadButton.left,
      if (buttons & _dpadRight != 0 || lx > _stickDeadzone) PadButton.right,
      if (buttons & _a != 0) PadButton.a,
      if (buttons & _b != 0) PadButton.b,
      if (buttons & _x != 0) PadButton.x,
      if (buttons & _y != 0) PadButton.y,
      if (buttons & _start != 0) PadButton.start,
      if (buttons & _back != 0) PadButton.view,
      if (buttons & _lb != 0) PadButton.lb,
      if (buttons & _rb != 0) PadButton.rb,
    };

    for (final b in down) {
      if (!_held.contains(b)) {
        _controller.add(b); // fresh press
        _nextRepeat[b] = now.add(_repeatDelay);
      } else if (_isDirection(b) && now.isAfter(_nextRepeat[b]!)) {
        _controller.add(b); // held direction auto-repeats, like a remote
        _nextRepeat[b] = now.add(_repeatEvery);
      }
    }
    _held = down;
  }

  static bool _isDirection(PadButton b) =>
      b == PadButton.up ||
      b == PadButton.down ||
      b == PadButton.left ||
      b == PadButton.right;
}
