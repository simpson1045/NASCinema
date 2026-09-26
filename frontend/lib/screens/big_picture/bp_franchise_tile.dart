import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/franchise.dart';
import '../../theme/app_theme.dart';

/// A Disney+-style franchise tile for the home row: the franchise's logo over
/// a backdrop. Highlighted, it grows and the backdrop becomes a slow
/// pan-and-zoom ("Ken Burns") slideshow through the franchise's movies,
/// crossfading every few seconds; only the focused tile animates.
class BpFranchiseTile extends StatefulWidget {
  const BpFranchiseTile({
    super.key,
    required this.franchise,
    required this.focused,
    required this.onTap,
    this.width = 480,
    this.height = 270,
  });

  final Franchise franchise;
  final bool focused;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<BpFranchiseTile> createState() => _BpFranchiseTileState();
}

class _BpFranchiseTileState extends State<BpFranchiseTile> {
  static const _slide = Duration(seconds: 4);
  Timer? _timer;
  int _index = 0;

  List<String> get _images {
    final urls = widget.franchise.backdropUrls();
    if (urls.isNotEmpty) return urls;
    final b = widget.franchise.backdrop;
    return b == null ? const [] : [b];
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BpFranchiseTile old) {
    super.didUpdateWidget(old);
    if (old.focused != widget.focused) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (widget.focused && _images.length > 1) {
      _timer = Timer.periodic(_slide, (_) {
        if (mounted) setState(() => _index = (_index + 1) % _images.length);
      });
    } else if (!widget.focused && _index != 0) {
      setState(() => _index = 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.franchise;
    final images = _images;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: widget.focused ? 1.06 : 1.0,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: NasColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: widget.focused ? Colors.white : Colors.transparent,
                      width: 4),
                  boxShadow: widget.focused
                      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 24)]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (images.isNotEmpty)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 900),
                        child: _KenBurns(
                          key: ValueKey('$_index-${widget.focused}'),
                          url: images[_index % images.length],
                          animate: widget.focused,
                          // Alternate the drift direction slide to slide.
                          flip: _index.isOdd,
                          duration: _slide + const Duration(seconds: 1),
                        ),
                      ),
                    // Dim so the logo reads; lighter when highlighted.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      color: Colors.black.withValues(alpha: widget.focused ? 0.25 : 0.5),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(34),
                      child: f.logo != null
                          ? Image.network(f.logo!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => _name(f))
                          : _name(f),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: widget.focused ? Colors.white : NasColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w700)),
            Text(
                [
                  '${f.count} movies',
                  if (f.years != null) f.years!,
                ].join('  ·  '),
                style: const TextStyle(color: NasColors.muted, fontSize: 22)),
          ],
        ),
      ),
    );
  }

  Widget _name(Franchise f) => Center(
        child: Text(f.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(blurRadius: 12, color: Colors.black)])),
      );
}

/// One backdrop drifting and slowly zooming (still when not animating).
class _KenBurns extends StatelessWidget {
  const _KenBurns({
    super.key,
    required this.url,
    required this.animate,
    required this.flip,
    required this.duration,
  });

  final String url;
  final bool animate;
  final bool flip;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink());
    if (!animate) return image;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeInOut,
      builder: (_, t, child) {
        final scale = 1.05 + 0.12 * t;
        final dx = (flip ? -1 : 1) * (t - 0.5) * 24;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: image,
    );
  }
}
