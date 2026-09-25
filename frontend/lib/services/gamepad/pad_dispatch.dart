import 'package:flutter/widgets.dart';

import 'gamepad.dart';

export 'gamepad.dart';

/// Returns true when it consumed the press.
typedef PadHandler = bool Function(PadButton button);

/// Routes controller presses. A screen with its own navigation model (big
/// picture) registers a handler and takes the presses while it's in charge;
/// otherwise the pad drives ordinary focus — D-pad moves between controls,
/// A activates, B goes back — so the controller never strands you on a
/// dialog or a page that wasn't built for it.
class PadDispatch {
  PadDispatch._();

  static final List<PadHandler> _handlers = [];
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    Gamepad.instance.start();
    Gamepad.instance.presses.listen(_dispatch);
  }

  static void add(PadHandler h) => _handlers.add(h);

  static void remove(PadHandler h) => _handlers.remove(h);

  static void _dispatch(PadButton b) {
    for (final h in _handlers.reversed) {
      if (h(b)) return;
    }
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    switch (b) {
      case PadButton.up:
        node?.focusInDirection(TraversalDirection.up);
      case PadButton.down:
        node?.focusInDirection(TraversalDirection.down);
      case PadButton.left:
        node?.focusInDirection(TraversalDirection.left);
      case PadButton.right:
        node?.focusInDirection(TraversalDirection.right);
      case PadButton.a:
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      case PadButton.b:
      case PadButton.view:
        if (ctx != null) Navigator.maybeOf(ctx)?.maybePop();
      default:
        break;
    }
  }
}
