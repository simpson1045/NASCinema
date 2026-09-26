import 'package:flutter/widgets.dart';

import '../flag_service.dart';
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
    Gamepad.instance.scroll.listen(_scrollPage);
  }

  /// Right stick: scroll whatever vertical list the focused page has — the
  /// one around the focus, else the first one inside it. Up to ~1700 px/s.
  static void _scrollPage(double v) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return;
    final s = _verticalScrollable(ctx);
    if (s == null) return;
    final p = s.position;
    final to = (p.pixels - v * 28).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) p.jumpTo(to);
  }

  static ScrollableState? _verticalScrollable(BuildContext ctx) {
    bool vertical(ScrollableState s) =>
        axisDirectionToAxis(s.axisDirection) == Axis.vertical;
    final up = Scrollable.maybeOf(ctx);
    if (up != null && vertical(up)) return up;
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (vertical(s)) {
          found = s;
          return;
        }
      }
      e.visitChildren(visit);
    }

    (ctx as Element).visitChildren(visit);
    return found;
  }

  static void add(PadHandler h) => _handlers.add(h);

  static void remove(PadHandler h) => _handlers.remove(h);

  static void _dispatch(PadButton b) {
    // View is the flag button everywhere — nothing else gets it.
    if (b == PadButton.view) {
      FlagService.flag();
      return;
    }
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
        if (ctx != null) Navigator.maybeOf(ctx)?.maybePop();
      default:
        break;
    }
  }
}
