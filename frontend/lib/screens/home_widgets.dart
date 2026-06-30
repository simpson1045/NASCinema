import 'dart:async';

import 'package:flutter/material.dart';

import '../models/home.dart';
import '../models/movie.dart';
import '../theme/app_theme.dart';
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

/// Auto-advancing featured banner: backdrop + clearlogo (or title) + ratings +
/// a Play button, with manual arrows and paging dots. (Trailer autoplay is a
/// Phase 2 follow-up; this is the static hero.)
class FeaturedHero extends StatefulWidget {
  const FeaturedHero({super.key, required this.featured, required this.baseUrl});

  final List<Movie> featured;
  final String baseUrl;

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<FeaturedHero> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    if (widget.featured.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => _go(1));
    }
  }

  void _go(int dir) {
    final n = widget.featured.length;
    if (n == 0) return;
    setState(() => _i = (_i + dir + n) % n);
  }

  void _manual(int dir) {
    _go(dir);
    _start(); // reset the dwell after a manual move
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.featured[_i];
    final double h =
        (MediaQuery.of(context).size.height * 0.5).clamp(360.0, 560.0).toDouble();
    return SizedBox(
      height: h,
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
          const _HeroScrim(),
          Positioned(
            left: 40,
            right: 40,
            bottom: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _HeroContent(
                key: ValueKey('ct${m.id}'),
                movie: m,
                onPlay: () => _openMovie(context, m, widget.baseUrl),
              ),
            ),
          ),
          if (widget.featured.length > 1) ...[
            _HeroArrow(left: true, onTap: () => _manual(-1)),
            _HeroArrow(left: false, onTap: () => _manual(1)),
            Positioned(
              right: 40,
              bottom: 18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int k = 0; k < widget.featured.length; k++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _i = k);
                        _start();
                      },
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
        ],
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
        _titleOrLogo(movie),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: ratingChips(movie)),
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
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 130),
        child: Image.network(
          m.logo!,
          alignment: Alignment.centerLeft,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _titleText(m),
        ),
      );
    }
    return _titleText(m);
  }

  Widget _titleText(Movie m) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Text(
          m.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
