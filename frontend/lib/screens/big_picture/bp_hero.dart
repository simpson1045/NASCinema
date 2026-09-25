import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/movie.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../hero_trailer.dart';

/// Big picture's featured hero — a port of the Roku FeaturedHero, laid out on
/// the same 1920x1080 canvas. It always fills the whole screen behind the
/// rails: on home the info sits upper-left and a gradient fades the picture
/// into the rails; [fullscreen] (hero focused) moves the info lower-left,
/// hides the rails and unmutes the trailer.
///
/// Trailers are never zoomed or cropped. A letterboxed one (server-measured
/// [Movie.trailerBars]) slides up by its top bar on home so the picture starts
/// at the top edge; fullscreen centers it like a movie.
class BpHero extends StatefulWidget {
  const BpHero({
    super.key,
    required this.featured,
    required this.baseUrl,
    required this.fullscreen,
  });

  final List<Movie> featured;
  final String baseUrl;
  final bool fullscreen;

  @override
  State<BpHero> createState() => BpHeroState();
}

class BpHeroState extends State<BpHero> {
  late List<Movie> _items;
  int _i = 0;

  late final TrailerPlayer _trailer = TrailerPlayer(
    onFirstFrame: _onTrailerFrames,
    onFinished: () => advance(1),
    onError: _stopTrailer,
  );
  bool _trailerShown = false; // first frame rendered → dissolve to video
  bool _faderOpaque = false; // black cover for advance/mode transitions
  bool _fading = false;
  bool _suspended = false; // a route covers big picture — no video underneath
  late bool _full = widget.fullscreen; // applied under the fader

  Timer? _dwell; // fallback advance / idle trailer cap
  Timer? _trailerDelay; // the backdrop "beat" before the trailer starts
  Timer? _routePoll; // isCurrent has no change notification — poll it

  // Follow mode: while browsing the rails the hero shows the highlighted
  // movie (Netflix-style) instead of cycling the featured list.
  Movie? _follow;
  Timer? _followDebounce; // fast scrolling doesn't thrash backdrops/trailers
  final Map<int, String?> _logos = {}; // rail items carry no logo — fetched once
  late final ApiService _api = ApiService(widget.baseUrl);

  /// The movie currently shown (null when there's nothing featured).
  Movie? get current =>
      _follow ?? (_items.isEmpty ? null : _items[_i]);

  /// Show [movie] (the highlighted rail tile) — or null to go back to the
  /// featured rotation. Backdrop crossfades after a short settle; its trailer
  /// follows after the usual beat if the server has one cached.
  void follow(Movie? movie) {
    _followDebounce?.cancel();
    if (movie == null) {
      if (_follow == null) return;
      _follow = null;
      _showItem();
      return;
    }
    if (movie.id == _follow?.id) return;
    _followDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _follow = movie;
      _dwell?.cancel(); // no auto-advance while browsing
      _stopTrailer();
      setState(() {});
      _trailerDelay?.cancel();
      if (!_suspended && _trailer.supported) {
        _trailerDelay =
            Timer(const Duration(milliseconds: 1400), _playTrailer);
      }
      if (movie.logo == null && !_logos.containsKey(movie.id)) {
        _logos[movie.id] = null;
        _api.getMovieDetail(movie.id).then((d) {
          if (mounted && d.logo != null) setState(() => _logos[movie.id] = d.logo);
        }).catchError((_) {});
      }
    });
  }

  String? _logoFor(Movie m) => m.logo ?? _logos[m.id];

  @override
  void initState() {
    super.initState();
    _items = [...widget.featured]..shuffle(Random());
    _routePoll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrent == _suspended) {
        _suspended = !isCurrent;
        if (_suspended) {
          _stopTrailer();
          _dwell?.cancel();
        } else {
          _showItem();
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showItem());
  }

  @override
  void didUpdateWidget(BpHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen != widget.fullscreen) {
      _setFullscreen(widget.fullscreen);
    }
  }

  @override
  void dispose() {
    for (final t in [_dwell, _trailerDelay, _routePoll, _followDebounce]) {
      t?.cancel();
    }
    _trailer.dispose();
    super.dispose();
  }

  void _showItem() {
    if (_items.isEmpty || !mounted) return;
    _stopTrailer();
    setState(() {});
    _dwell?.cancel();
    if (_follow != null) {
      // Browsing the rails: the followed movie stays; only its trailer resumes.
      _trailerDelay?.cancel();
      if (!_suspended && _trailer.supported) {
        _trailerDelay = Timer(const Duration(milliseconds: 1400), _playTrailer);
      }
      return;
    }
    _dwell = Timer(Duration(seconds: _full ? 15 : 25), () => advance(1));
    _trailerDelay?.cancel();
    if (!_suspended && _trailer.supported) {
      _trailerDelay = Timer(const Duration(milliseconds: 1400), _playTrailer);
    }
  }

  void _playTrailer() {
    final m = current;
    if (_suspended || !mounted || m == null) return;
    // Only trailers already cached server-side — never wait on a download.
    if (!m.trailerReady || m.trailerUrl == null) return;
    if (_follow != null && _follow!.id != m.id) return;
    _trailer.open('${widget.baseUrl}${m.trailerUrl}', muted: !_full);
  }

  void _onTrailerFrames() {
    if (!mounted) return;
    setState(() => _trailerShown = true);
    _dwell?.cancel();
    if (!_full) {
      // Idle: a 25s cap from playback start; fullscreen lets it play out.
      _dwell = Timer(const Duration(seconds: 25), () => advance(1));
    }
  }

  void _stopTrailer() {
    _trailerDelay?.cancel();
    _trailer.stop();
    if (mounted && _trailerShown) setState(() => _trailerShown = false);
  }

  /// Fade to black, run [swap] under the cover, fade back — the Roku fader.
  void _fadeThrough(VoidCallback swap) {
    if (_fading || !mounted) return;
    _fading = true;
    setState(() => _faderOpaque = true);
    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      swap();
      setState(() => _faderOpaque = false);
      Timer(const Duration(milliseconds: 300), () => _fading = false);
    });
  }

  /// Next/previous featured movie (Left/Right on the hero, or the timer).
  void advance(int dir) {
    if (_follow != null) return; // browsing the rails: no rotation
    if (_items.length < 2 || _fading) return;
    _fadeThrough(() {
      _i = (_i + dir + _items.length) % _items.length;
      _showItem();
    });
  }

  void _setFullscreen(bool full) {
    _trailer.setMuted(!full); // unmute instantly (Roku parity)
    _fadeThrough(() {
      _full = full;
      _dwell?.cancel();
      if (!(_full && _trailerShown)) {
        _dwell = Timer(Duration(seconds: _trailerShown || !_full ? 25 : 15),
            () => advance(1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = current;
    if (m == null) return const ColoredBox(color: NasColors.bg);
    final video = _trailerShown ? _trailer.view(fit: BoxFit.contain) : null;
    final shift = _full ? 0.0 : (m.trailerBars?.top ?? 0) * 1080;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          layoutBuilder: (cur, prev) =>
              Stack(fit: StackFit.expand, children: [...prev, ?cur]),
          child: _Backdrop(key: ValueKey('bd${m.id}'), movie: m),
        ),
        // Black behind a playing trailer so nothing shows around a
        // letterboxed picture; the backdrop is hidden underneath it.
        if (video != null) ...[
          const ColoredBox(color: Colors.black),
          Transform.translate(offset: Offset(0, -shift), child: video),
        ],
        _full ? const _FullscreenScrim() : const _HomeScrim(),
        if (_full)
          Positioned(
            left: 90,
            bottom: 70,
            child: _Info(movie: m, logo: _logoFor(m), compact: true),
          )
        else
          Positioned(
            left: 90,
            top: 110,
            child: _Info(
              movie: m,
              logo: _logoFor(m),
              compact: false,
              dots: _follow == null && _items.length > 1
                  ? _Dots(count: _items.length, index: _i)
                  : null,
            ),
          ),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _faderOpaque ? 1 : 0,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final url = movie.backdropUrl(size: 'original');
    if (url == null) return const ColoredBox(color: NasColors.surfaceRaised);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: NasColors.surfaceRaised),
    );
  }
}

/// Home: fade the picture into the rails (bottom) and darken the left for the
/// logo + overview — the same curve as the Roku's home_scrim2.png.
class _HomeScrim extends StatelessWidget {
  const _HomeScrim();

  @override
  Widget build(BuildContext context) {
    const navy = NasColors.bg;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  navy.withValues(alpha: 0),
                  navy.withValues(alpha: 0),
                  navy.withValues(alpha: 0.90),
                  navy,
                ],
                stops: const [0.0, 0.30, 0.62, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [navy.withValues(alpha: 0.90), navy.withValues(alpha: 0)],
                stops: const [0.0, 0.62],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen: just enough dark in the lower-left for the logo + ratings.
class _FullscreenScrim extends StatelessWidget {
  const _FullscreenScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.bottomLeft,
            radius: 1.3,
            colors: [Color(0xD0000000), Color(0x00000000)],
            stops: [0.0, 0.6],
          ),
        ),
      ),
    );
  }
}

/// Logo (or title), ratings row, and — on home — the overview + paging dots.
class _Info extends StatelessWidget {
  const _Info(
      {required this.movie, required this.compact, this.logo, this.dots});

  final Movie movie;
  final String? logo;
  final bool compact;
  final Widget? dots;

  @override
  Widget build(BuildContext context) {
    final overview = movie.overview ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 520, height: 150, child: _logoOrTitle()),
        const SizedBox(height: 22),
        bpMetaRow(movie),
        if (!compact && overview.isNotEmpty) ...[
          const SizedBox(height: 22),
          SizedBox(
            width: 760,
            child: Text(
              overview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFDDE2F5),
                fontSize: 27,
                height: 1.3,
              ),
            ),
          ),
        ],
        if (!compact && dots != null) ...[const SizedBox(height: 26), dots!],
      ],
    );
  }

  Widget _logoOrTitle() {
    final title = Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        movie.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 60,
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
    );
    final logo = this.logo;
    if (logo == null || logo.isEmpty) return title;
    return Image.network(
      logo,
      fit: BoxFit.contain,
      alignment: Alignment.bottomLeft,
      errorBuilder: (_, _, _) => title,
    );
  }
}

/// Year · IMDb · RT · quality, sized for the couch (matches the Roku meta row).
Widget bpMetaRow(Movie m) {
  const text = TextStyle(
      color: NasColors.text, fontSize: 30, fontWeight: FontWeight.w700);
  final parts = <Widget>[
    if (m.year != null) Text('${m.year}', style: text),
    if (m.imdbRating != null)
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF5C518),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('IMDb',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Text(m.imdbRating!.toStringAsFixed(1), style: text),
      ]),
    if (m.rtScore != null)
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle,
            size: 22,
            color: m.rtScore! >= 60
                ? const Color(0xFFFA320A)
                : const Color(0xFF12A150)),
        const SizedBox(width: 8),
        Text('${m.rtScore}%', style: text),
      ]),
    if (m.qualityBadge != null) Text(m.qualityBadge!, style: text),
  ];
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int k = 0; k < parts.length; k++) ...[
        if (k > 0) const SizedBox(width: 26),
        parts[k],
      ],
    ],
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int k = 0; k < count; k++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 10),
            color: k == index ? NasColors.amber : Colors.white38,
          ),
      ],
    );
  }
}
