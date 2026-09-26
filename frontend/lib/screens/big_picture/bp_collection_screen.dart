import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/franchise.dart';
import '../../models/movie.dart';
import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';
import 'bp_hero.dart' show bpLogoOver;
import 'bp_movie_screen.dart';

/// A franchise page (Star Wars, Harry Potter …): its backdrop, logo centred
/// over "8 movies · 2001–2011", the overview, and the movies in release
/// order. ◀▶ move · A open · B back.
class BpCollectionScreen extends StatefulWidget {
  const BpCollectionScreen({
    super.key,
    required this.baseUrl,
    required this.franchise,
    this.fetch = true,
  });

  final String baseUrl;
  // What the home row already knows; the full page (with movies) is fetched.
  final Franchise franchise;
  final bool fetch;

  @override
  State<BpCollectionScreen> createState() => _BpCollectionScreenState();
}

class _BpCollectionScreenState extends State<BpCollectionScreen> {
  final _focus = FocusNode(debugLabel: 'bp-collection');
  late Franchise _f = widget.franchise;
  int _item = 0;
  bool _loading = true;

  static const _posterW = 240.0, _posterH = 360.0, _gap = 30.0;

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-collection', widget.baseUrl, () {
      final m = _f.movies.isEmpty ? null : _f.movies[_item];
      return {
        'collection': _f.name,
        'movie_id': m?.id,
        'movie_title': m?.title,
      };
    });
    _load();
  }

  Future<void> _load() async {
    if (widget.fetch) {
      try {
        final full = await ApiService(widget.baseUrl).getCollection(_f.id);
        if (mounted) setState(() => _f = full);
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(Movie m) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BpMovieScreen(movie: m, baseUrl: widget.baseUrl),
    ));
    if (mounted) _focus.requestFocus();
  }

  bool _onPad(PadButton b) {
    final n = _f.movies.length;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.left:
        if (_item > 0) setState(() => _item--);
      case PadButton.right:
        if (_item < n - 1) setState(() => _item++);
      case PadButton.a:
        if (n > 0) _open(_f.movies[_item]);
      default:
        break;
    }
    return true;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final b = {
      LogicalKeyboardKey.arrowLeft: PadButton.left,
      LogicalKeyboardKey.arrowRight: PadButton.right,
      LogicalKeyboardKey.enter: PadButton.a,
      LogicalKeyboardKey.escape: PadButton.b,
      LogicalKeyboardKey.backspace: PadButton.b,
    }[e.logicalKey];
    if (b == null) return KeyEventResult.ignored;
    _onPad(b);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NasColors.bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: ClipRect(child: _canvas()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas() {
    final backdrop = _f.backdrop ??
        (_f.movies.isNotEmpty ? _f.movies.first.backdropUrl(size: 'original') : null);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          Image.network(backdrop,
              fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x660A0E27), Color(0xCC0A0E27), Color(0xFF0A0E27)],
              stops: [0.0, 0.45, 0.72],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xCC0A0E27), Color(0x000A0E27)],
              stops: [0.0, 0.6],
            ),
          ),
        ),
        Positioned(
          left: 90,
          top: 90,
          width: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo centred over its line (house rule).
              bpLogoOver(
                logo: _logo(),
                below: Text(
                  [
                    '${_f.count} movies',
                    if (_f.years != null) _f.years!,
                  ].join('  ·  '),
                  style: const TextStyle(
                      color: NasColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w700),
                ),
                logoHeight: 170,
                gap: 22,
                maxWidth: 760,
              ),
              if ((_f.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: 26),
                SizedBox(
                  width: 1000,
                  child: Text(_f.overview!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFDDE2F5), fontSize: 28, height: 1.35)),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 560,
          height: 440,
          child: _loading && _f.movies.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: NasColors.amber))
              : _rail(),
        ),
        const Positioned(
          left: 90,
          bottom: 40,
          child: PadHints([
            (PadGlyph.dpadHorizontal, 'Browse'),
            (PadGlyph.a, 'Open'),
            (PadGlyph.b, 'Back'),
          ], size: 30, fontSize: 20),
        ),
      ],
    );
  }

  Widget _logo() {
    final title = Align(
      alignment: Alignment.bottomCenter,
      child: Text(_f.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
              color: Colors.white, fontSize: 72, fontWeight: FontWeight.w800)),
    );
    final logo = _f.logo;
    if (logo == null) return title;
    return Image.network(logo,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        errorBuilder: (_, _, _) => title);
  }

  Widget _rail() {
    final ms = _f.movies;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: 90 - _item * (_posterW + _gap),
          top: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < ms.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                _poster(ms[i], i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _poster(Movie m, int i) {
    final focused = i == _item;
    final url = m.posterUrl(size: 'w500');
    return GestureDetector(
      onTap: () {
        setState(() => _item = i);
        _open(m);
      },
      child: SizedBox(
        width: _posterW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: focused ? 1.08 : 1,
              child: Container(
                width: _posterW,
                height: _posterH,
                decoration: BoxDecoration(
                  color: NasColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: focused ? Colors.white : Colors.transparent, width: 4),
                ),
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? Center(
                        child: Text(m.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 24)))
                    : Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
            const SizedBox(height: 14),
            Text(m.year != null ? '${m.year}' : '',
                style: TextStyle(
                    color: focused ? NasColors.amber : NasColors.muted,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            Text(m.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: focused ? Colors.white : NasColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
