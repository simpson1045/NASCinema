import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/gamepad/gamepad.dart';

/// Hides the mouse cursor as soon as the controller or keyboard is used, and
/// brings it back the moment the mouse moves — so the cursor never sits on
/// top of big picture while you drive it from the couch, and mouse support
/// still just works.
///
/// The hiding layer sits ON TOP of the app: a cursor set lower down would be
/// overridden by every button's own click cursor. It's translucent to hits,
/// so clicks and hovers still reach the app underneath.
class CursorAutoHide extends StatefulWidget {
  const CursorAutoHide({super.key, required this.child});

  final Widget child;

  @override
  State<CursorAutoHide> createState() => _CursorAutoHideState();
}

class _CursorAutoHideState extends State<CursorAutoHide> {
  bool _hidden = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(Gamepad.instance.presses.listen((_) => _hide()));
    _subs.add(Gamepad.instance.scroll.listen((_) => _hide()));
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) _hide();
    return false; // never consume — just watching
  }

  void _hide() {
    if (!_hidden && mounted) setState(() => _hidden = true);
  }

  void _onPointer(PointerEvent e) {
    if (_hidden && e.kind == PointerDeviceKind.mouse) {
      setState(() => _hidden = false);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: _onPointer,
      onPointerMove: _onPointer,
      onPointerDown: _onPointer,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: MouseRegion(
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              cursor: _hidden ? SystemMouseCursors.none : MouseCursor.defer,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
