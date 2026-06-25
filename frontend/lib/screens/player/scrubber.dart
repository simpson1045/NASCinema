import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// Translucent layers as literal ARGB so we avoid withOpacity/withValues churn.
const _cachedColor = Color(0x4DFFB020); // amber @ 30% — converted on server
const _bufferedColor = Color(0x8CB46BFF); // violet @ 55% — buffered in browser

/// A seek bar that paints three layers — converted-on-server, buffered-in-
/// browser, and played — and seeks on tap/drag.
class Scrubber extends StatefulWidget {
  final double duration;
  final double position;
  final List<double> buffered; // flat [start, end, ...]
  final List<List<double>> cached; // [[start, end], ...]
  final ValueChanged<double> onSeek;

  const Scrubber({
    super.key,
    required this.duration,
    required this.position,
    required this.buffered,
    required this.cached,
    required this.onSeek,
  });

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  double? _dragFraction;

  void _setFromDx(double dx, double width) {
    setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
  }

  void _commit() {
    final f = _dragFraction;
    if (f != null && widget.duration > 0) widget.onSeek(f * widget.duration);
    setState(() => _dragFraction = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final fraction = _dragFraction ??
            (widget.duration > 0
                ? (widget.position / widget.duration).clamp(0.0, 1.0)
                : 0.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _setFromDx(d.localPosition.dx, width);
            _commit();
          },
          onHorizontalDragStart: (d) => _setFromDx(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _setFromDx(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _commit(),
          child: SizedBox(
            height: 34,
            width: width,
            child: CustomPaint(
              painter: _ScrubberPainter(
                duration: widget.duration,
                fraction: fraction,
                buffered: widget.buffered,
                cached: widget.cached,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  final double duration;
  final double fraction;
  final List<double> buffered;
  final List<List<double>> cached;

  _ScrubberPainter({
    required this.duration,
    required this.fraction,
    required this.buffered,
    required this.cached,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    const h = 6.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - h / 2, w, h),
      const Radius.circular(3),
    );
    canvas.drawRRect(track, Paint()..color = NasColors.surfaceRaised);
    if (duration <= 0) return;

    final px = w / duration; // pixels per second
    canvas.save();
    canvas.clipRRect(track);

    void band(double a, double b, Paint p) {
      final x0 = (a * px).clamp(0.0, w);
      final x1 = (b * px).clamp(0.0, w);
      if (x1 > x0) canvas.drawRect(Rect.fromLTRB(x0, cy - h / 2, x1, cy + h / 2), p);
    }

    final cachedPaint = Paint()..color = _cachedColor;
    for (final seg in cached) {
      band(seg[0], seg[1], cachedPaint);
    }
    final bufferedPaint = Paint()..color = _bufferedColor;
    for (var i = 0; i + 1 < buffered.length; i += 2) {
      band(buffered[i], buffered[i + 1], bufferedPaint);
    }
    final playedX = fraction.clamp(0.0, 1.0) * w;
    canvas.drawRect(
      Rect.fromLTRB(0, cy - h / 2, playedX, cy + h / 2),
      Paint()..color = NasColors.amber,
    );
    canvas.restore();

    final cx = fraction.clamp(0.0, 1.0) * w;
    canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = NasColors.amber);
    canvas.drawCircle(
      Offset(cx, cy),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.fraction != fraction ||
      old.duration != duration ||
      old.cached != cached ||
      old.buffered != buffered;
}
