import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/home.dart';
import '../models/movie.dart';
import '../theme/app_theme.dart';
import 'big_picture/bp_hero.dart' show bpLogoOver;
import 'hero_trailer.dart';
import 'movie_detail_screen.dart';

/// The carousel home body — featured hero over horizontal rails. Mirrors the
/// Roku home (same `/api/home` payload), presented for desktop/web/mobile.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.data, required this.baseUrl});

  final HomeData data;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (data.featured.isNotEmpty)
          FeaturedHero(featured: data.featured, baseUrl: baseUrl),
        for (final rail in data.rails)
          if (rail.movies.isNotEmpty) MovieRail(rail: rail, baseUrl: baseUrl),
        const SizedBox(height: 28),
      ],
    );
  }
}

void _openMovie(BuildContext context, Movie m, String baseUrl) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(movie: m, baseUrl: baseUrl),
    ));

// ─────────────────────────────────────────────────────────────────────────────
// Featured hero
// ─────────────────────────────────────────────────────────────────────────────

/// The featured hero, ported from the Roku FeaturedHero (the design source of
/// truth): backdrop + clearlogo + ratings + Play over an auto-advancing,
/// shuffled featured list — and where the platform supports it, each item's
/// cached trailer starts after a beat and dissolves in over the backdrop.
/// Hovering the hero expands it to fill the viewport and unmutes the trailer
/// (the mouse equivalent of the Roku's focus-to-fullscreen); every advance
/// and mode change goes through a fade-to-black so nothing snaps.
class FeaturedHero extends StatefulWidget {
  const FeaturedHero({super.key, required this.featured, required this.baseUrl});

  final List<Movie> featured;
  final String baseUrl;

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<FeaturedHero> {
  late List<Movie> _items;
  int _i = 0;

  late final TrailerPlayer _trailer = TrailerPlayer(
    onFirstFrame: _onTrailerFrames,
    onFinished: () => _advance(1),
    onError: _stopTrailer,
  );
  bool _trailerShown = false; // first frame rendered → dissolve to video

  bool _active = false; // hover-fullscreen mode (unmuted, no auto-advance cap)
  bool _faderOpaque = false; // the black cover for advance/mode transitions
  bool _fading = false; // debounce overlapping advances (Roku parity)
  bool _suspended = false; // a route is pushed over home — no video underneath

  Timer? _dwell; // fallback advance / idle trailer cap
  Timer? _trailerDelay; // the backdrop "beat" before the trailer starts
  Timer? _hoverDelay; // hover must settle before fullscreen engages
  Timer? _routePoll; // isCurrent has no change notification — poll it

  @override
  void initState() {
    super.initState();
    // Shuffled copy so every launch scrolls a different order (Roku parity).
    _items = [...widget.featured]..shuffle(Random());
    // Suspend while a pushed route (detail/player) covers home: two videos
    // must never fight, and hero audio under a movie would be absurd.
    _routePoll = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = ModalRoute.of(context)?.isCurrent ?? true;
      if (current == _suspended) {
        _suspended = !current;
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
  void didUpdateWidget(FeaturedHero old) {
    super.didUpdateWidget(old);
    if (!identical(old.featured, widget.featured)) {
      _items = [...widget.featured]..shuffle(Random());
      _i = 0;
      _showItem();
    }
  }

  @override
  void dispose() {
    for (final t in [_dwell, _trailerDelay, _hoverDelay, _routePoll]) {
      t?.cancel();
    }
    _trailer.dispose();
    super.dispose();
  }

  Movie get _movie => _items[_i];

  /// Show the current item: backdrop first, trailer after a beat. A fallback
  /// dwell timer always runs so a missing/broken trailer still advances us.
  void _showItem() {
    if (_items.isEmpty || !mounted) return;
    _stopTrailer();
    setState(() {});
    _dwell?.cancel();
    _dwell = Timer(Duration(seconds: _active ? 15 : 25), () => _advance(1));
    _trailerDelay?.cancel();
    if (!_suspended && _trailer.supported) {
      _trailerDelay = Timer(const Duration(milliseconds: 2500), _playTrailer);
    }
  }

  void _playTrailer() {
    if (_suspended || !mounted) return;
    final m = _movie;
    // Only trailers already cached server-side — never wait on a download.
    if (!m.trailerReady || m.trailerUrl == null) return;
    _trailer.open('${widget.baseUrl}${m.trailerUrl}', muted: !_active);
  }

  void _onTrailerFrames() {
    if (!mounted) return;
    setState(() => _trailerShown = true);
    _dwell?.cancel();
    if (!_active) {
      // Idle: a 25s cap from playback start; fullscreen lets it play out.
      _dwell = Timer(const Duration(seconds: 25), () => _advance(1));
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
    Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      swap();
      setState(() => _faderOpaque = false);
      Timer(const Duration(milliseconds: 280), () => _fading = false);
    });
  }

  void _advance(int dir) {
    if (_items.isEmpty || _fading) return;
    _fadeThrough(() {
      _i = (_i + dir + _items.length) % _items.length;
      _showItem();
    });
  }

  void _jumpTo(int k) {
    if (k == _i || _fading) return;
    _fadeThrough(() {
      _i = k;
      _showItem();
    });
  }

  void _setActive(bool active) {
    _hoverDelay?.cancel();
    if (active == _active) return;
    _trailer.setMuted(!active); // unmute instantly on hover (Roku parity)
    _fadeThrough(() {
      _active = active;
      _dwell?.cancel();
      if (_active && _trailerShown) {
        // Fullscreen: the trailer plays to its end, no cap.
      } else {
        _dwell = Timer(
            Duration(seconds: _trailerShown || !_active ? 25 : 15),
            () => _advance(1));
      }
    });
  }

  void _onHover(bool inside) {
    _hoverDelay?.cancel();
    if (inside) {
      // Engage fullscreen only after the pointer settles on the hero — a
      // mouse just passing through to the rails shouldn't blow it up.
      _hoverDelay = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _trailerShown) _setActive(true);
      });
    } else {
      _setActive(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _movie;
    final mq = MediaQuery.of(context);
    final double banner =
        (mq.size.height * 0.5).clamp(360.0, 560.0).toDouble();
    final double full =
        max(banner, mq.size.height - mq.padding.top - kToolbarHeight);
    final trailerView = _trailerShown ? _trailer.view() : null;

    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: _active ? full : banner,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              // Expand the crossfade stack so the backdrop fills edge-to-edge
              // instead of sizing to the image and centering (black side bars).
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: _Backdrop(
                  key: ValueKey('bd${m.id}'),
                  url: m.backdropUrl(size: 'w1280')),
            ),
            // The trailer dissolves in over the backdrop once frames flow.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: trailerView == null ? 0 : 1,
              child: trailerView ?? const SizedBox.shrink(),
            ),
            const _HeroScrim(),
            Positioned(
              left: 40,
              right: 40,
              bottom: 40,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                // The default layout CENTERS the child — the info must hug
                // the left edge like the Roku, not float mid-picture.
                layoutBuilder: (cur, prev) => Stack(
                  alignment: Alignment.bottomLeft,
                  children: [...prev, ?cur],
                ),
                child: _HeroContent(
                  key: ValueKey('ct${m.id}'),
                  movie: m,
                  onPlay: () => _openMovie(context, m, widget.baseUrl),
                ),
              ),
            ),
            if (_items.length > 1 && !_active) ...[
              _HeroArrow(left: true, onTap: () => _advance(-1)),
              _HeroArrow(left: false, onTap: () => _advance(1)),
              Positioned(
                right: 40,
                bottom: 18,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int k = 0; k < _items.length; k++)
                      GestureDetector(
                        onTap: () => _jumpTo(k),
                        child: Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: k == _i ? NasColors.amber : Colors.white24,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            // The black fader sits above everything: advances and
            // banner<->fullscreen swaps happen under it, never in view.
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: _faderOpaque ? 1 : 0,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const ColoredBox(color: NasColors.surfaceRaised);
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: NasColors.surfaceRaised),
    );
  }
}

/// Darkens the bottom (for text) and a touch on the left, fading to clear at top.
class _HeroScrim extends StatelessWidget {
  const _HeroScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xF20D0F14), Color(0x000D0F14)],
                stops: [0.0, 0.62],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xC00D0F14), Color(0x000D0F14)],
                stops: [0.0, 0.55],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({super.key, required this.movie, required this.onPlay});

  final Movie movie;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo centred over the rating chips (house rule).
        bpLogoOver(
          logo: _titleOrLogo(movie),
          below: Wrap(spacing: 8, runSpacing: 8, children: ratingChips(movie)),
          logoHeight: 130,
          gap: 14,
          minWidth: 300,
          maxWidth: 660,
        ),
        if (movie.overview != null && movie.overview!.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Text(
              movie.overview!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: NasColors.text, fontSize: 14, height: 1.35),
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onPlay,
          style: FilledButton.styleFrom(
            backgroundColor: NasColors.amber,
            foregroundColor: NasColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 24),
          label: const Text('Play',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _titleOrLogo(Movie m) {
    if (m.logo != null && m.logo!.isNotEmpty) {
      return Image.network(
        m.logo!,
        alignment: Alignment.bottomCenter,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _titleText(m),
      );
    }
    return _titleText(m);
  }

  Widget _titleText(Movie m) => Align(
        alignment: Alignment.bottomCenter,
        child: Text(
          m.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
      );
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 6 : null,
      right: left ? null : 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: Material(
          color: Colors.black26,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                left ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rails
// ─────────────────────────────────────────────────────────────────────────────

class MovieRail extends StatelessWidget {
  const MovieRail({super.key, required this.rail, required this.baseUrl});

  final HomeRail rail;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 10),
          child: Text(
            rail.title,
            style: const TextStyle(
                color: NasColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 252,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            itemCount: rail.movies.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) =>
                PosterTile(movie: rail.movies[i], baseUrl: baseUrl),
          ),
        ),
      ],
    );
  }
}

class PosterTile extends StatelessWidget {
  const PosterTile({super.key, required this.movie, required this.baseUrl});

  final Movie movie;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: GestureDetector(
        onTap: () => _openMovie(context, movie, baseUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  AspectRatio(aspectRatio: 2 / 3, child: _PosterImage(movie)),
                  if (movie.qualityBadge != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _chip(movie.qualityBadge!,
                          bg: NasColors.amber, fg: NasColors.bg),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: NasColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500),
            ),
            Text(
              [
                if (movie.year != null) '${movie.year}',
                if (movie.imdbRating != null)
                  '★ ${movie.imdbRating!.toStringAsFixed(1)}',
              ].join('  ·  '),
              style: const TextStyle(color: NasColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage(this.movie);

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final url = movie.posterUrl();
    Widget fallback() => const ColoredBox(
          color: NasColors.surfaceRaised,
          child: Icon(Icons.movie_outlined, color: NasColors.muted, size: 26),
        );
    if (url == null) return fallback();
    return Image.network(url,
        fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rating chips (text-based for now; logo art is a later polish)
// ─────────────────────────────────────────────────────────────────────────────

List<Widget> ratingChips(Movie m) {
  final chips = <Widget>[];
  if (m.year != null) chips.add(_chip('${m.year}'));
  final rl = m.runtimeLabel;
  if (rl != null) chips.add(_chip(rl));
  final q = m.qualityBadge;
  if (q != null) chips.add(_chip(q, bg: NasColors.amber, fg: NasColors.bg));
  if (m.imdbRating != null) {
    chips.add(_chip('IMDb ${m.imdbRating!.toStringAsFixed(1)}',
        bg: const Color(0xFFF5C518), fg: Colors.black));
  }
  if (m.rtScore != null) {
    // RT's own palette: fresh/certified = red tomato, rotten = green splat.
    final fresh = m.rtScore! >= 60;
    chips.add(_chip('RT ${m.rtScore}%',
        bg: fresh ? const Color(0xFFFA320A) : const Color(0xFF12A150),
        fg: Colors.white));
  }
  if (m.metacritic != null) {
    final s = m.metacritic!;
    final c = s >= 61
        ? const Color(0xFF66CC33)
        : (s >= 40 ? const Color(0xFFFFCC33) : const Color(0xFFFF6666));
    chips.add(_chip('Metacritic $s', bg: c, fg: Colors.black));
  }
  return chips;
}

Widget _chip(String text, {Color? bg, Color? fg}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: fg ?? NasColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600),
      ),
    );
