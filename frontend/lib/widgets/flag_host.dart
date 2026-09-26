import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/flag_service.dart';
import '../theme/app_theme.dart';

/// Wraps the whole app: the boundary a flag's screenshot is taken from, the
/// "Flagged ✓" toast (outside the boundary, so it's never in the picture),
/// and F8 as the keyboard flag key. The controller's View button is routed
/// here by PadDispatch.
class FlagHost extends StatefulWidget {
  const FlagHost({super.key, required this.child});

  final Widget child;

  @override
  State<FlagHost> createState() => _FlagHostState();
}

class _FlagHostState extends State<FlagHost> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f8) {
      FlagService.flag();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(key: FlagService.boundaryKey, child: widget.child),
        Positioned(
          top: 32,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: ValueListenableBuilder<String?>(
              valueListenable: FlagService.toast,
              builder: (_, text, _) => AnimatedOpacity(
                opacity: text == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: NasColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: NasColors.amber, width: 2),
                    ),
                    child: Text(
                      text ?? '',
                      style: const TextStyle(
                        color: NasColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
