import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';

/// The full description (a movie's or a franchise's), opened from the
/// highlighted overview on its page — the pages clip it to 3 lines. B, A or
/// Esc close it; ▲▼ scroll a very long one.
Future<void> showBpReadMore(BuildContext context,
    {required String title, String? subtitle, required String text}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: const Color(0xC0000000),
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    // A page route has no Material above it: without one, text falls back to
    // the yellow-underlined debug style.
    pageBuilder: (_, _, _) => Material(
        type: MaterialType.transparency,
        child: _BpReadMore(title: title, subtitle: subtitle, text: text)),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// The overview's highlight when it's the focused row: a frame drawn just
/// outside the text (so nothing moves) and "Ⓐ Read more" to its right.
/// [width] is the text block's width.
Widget bpOverviewFocus(
        {required Widget child, required bool focused, required double width}) =>
    Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (focused) ...[
          Positioned(
            left: -18,
            top: -12,
            right: -18,
            bottom: -12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
          Positioned(
            left: width + 40,
            bottom: 0,
            child: const PadHints([(PadGlyph.a, 'Read more')], size: 30, fontSize: 22),
          ),
        ],
      ],
    );

class _BpReadMore extends StatefulWidget {
  const _BpReadMore({required this.title, this.subtitle, required this.text});

  final String title;
  final String? subtitle;
  final String text;

  @override
  State<_BpReadMore> createState() => _BpReadMoreState();
}

class _BpReadMoreState extends State<_BpReadMore> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'bp-read-more');

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _by(double dy) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.animateTo((p.pixels + dy).clamp(0.0, p.maxScrollExtent),
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    switch (b) {
      case PadButton.a || PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.up:
        _by(-140);
      case PadButton.down:
        _by(140);
      default:
        break;
    }
    return true; // nothing reaches the page underneath
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.backspace ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.goBack) {
          Navigator.of(context).maybePop();
        } else if (k == LogicalKeyboardKey.arrowUp) {
          _by(-140);
        } else if (k == LogicalKeyboardKey.arrowDown) {
          _by(140);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: Center(
                child: Container(
                  width: 1240,
                  constraints: const BoxConstraints(maxHeight: 860),
                  padding: const EdgeInsets.fromLTRB(64, 52, 64, 40),
                  decoration: BoxDecoration(
                    color: NasColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: NasColors.amber, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 46,
                              fontWeight: FontWeight.w800)),
                      if ((widget.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(widget.subtitle!,
                            style: const TextStyle(
                                color: NasColors.muted, fontSize: 26)),
                      ],
                      const SizedBox(height: 28),
                      Flexible(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: Text(widget.text,
                              style: const TextStyle(
                                  color: Color(0xFFDDE2F5),
                                  fontSize: 32,
                                  height: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const PadHints([(PadGlyph.b, 'Close')], size: 30, fontSize: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
