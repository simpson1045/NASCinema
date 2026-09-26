import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Xbox controller glyphs (Kenney "Input Prompts", CC0 — the full pack lives in
/// third_party/kenney-input-prompts; the app ships only these).
enum PadGlyph {
  a('button_color_a'),
  b('button_color_b'),
  x('button_color_x'),
  y('button_color_y'),
  lb('lb'),
  rb('rb'),
  dpadHorizontal('dpad_horizontal'),
  dpadVertical('dpad_vertical'),
  dpadUp('dpad_up'),
  dpadDown('dpad_down'),
  dpadLeft('dpad_left'),
  dpadRight('dpad_right'),
  menu('button_menu'),
  view('button_view');

  const PadGlyph(this.file);
  final String file;

  String get asset => 'assets/prompts/xbox/xbox_$file.png';
}

/// One controller button, as the real Xbox glyph.
class PadIcon extends StatelessWidget {
  const PadIcon(this.glyph, {super.key, this.size = 34});

  final PadGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        glyph.asset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}

/// A row of button hints: [A] Choose   [◀▶] Column   [B] Done …
class PadHints extends StatelessWidget {
  const PadHints(this.items, {super.key, this.size = 34, this.fontSize = 22});

  final List<(PadGlyph, String)> items;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 34,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (glyph, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PadIcon(glyph, size: size),
              SizedBox(width: size * 0.3),
              Text(label,
                  style: TextStyle(
                      color: NasColors.muted,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none)),
            ],
          ),
      ],
    );
  }
}
