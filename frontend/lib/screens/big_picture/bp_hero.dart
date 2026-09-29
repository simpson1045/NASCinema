import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../models/movie.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../hero_reel.dart';
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
  // Fullscreen on Windows: trailers play in native mpv instead (the texture
  // path stutters at 24p — see HeroReel). Home stays on the texture player:
  // the rails draw over it, and nothing can draw over native video.
  late final HeroReel _reel = HeroReel(onFinished: () => advance(1));
  final _overlayKey = GlobalKey(); // scrim + info → bitmap for mpv's overlay
  bool get _reelMode => _full && _reel.supported;
  int _reelReq = 0; // bumps on every reel play/stop; stale results ignored
  static const _slide = Duration(milliseconds: 450); // home ↔ fullscreen
  DateTime _layoutSettled = DateTime.now(); // when that slide finishes
  bool _exitPending = false; // leaving fullscreen: waiting on the texture
  bool _trailerShown = false; // first frame rendered → dissolve to video
  bool _faderOpaque = false; // black cover for advance/mode transitions
  bool _fading = false;
  bool _suspended = false; // a route covers big picture — no video underneath
  bool _hold = false; // home opened a page (pauseForPage) — the poll stays out
  late bool _full = widget.fullscreen; // applied under the fader

  Timer? _dwell; // fallback advance / idle trailer cap
  Timer? _trailerDelay; // the backdrop "beat" before the trailer starts
  Timer? _routePoll; // isCurrent has no change notification — poll it

  // Follow mode: while browsing the rails the hero shows the highlighted
  // movie (Netflix-style) instead of cycling the featured list.
  Movie? _follow;
  Timer? _followDebounce; // fast scrolling doesn't thrash backdrops/trailers
  final Map<int, String?> _logos = {}; // rail items carry no logo — fetched once
  final Map<int, String?> _logoSubs = {};
  late final ApiService _api = ApiService(widget.baseUrl);

  /// The movie currently shown (null when there's nothing featured).
  Movie? get current =>
      _follow ?? (_items.isEmpty ? null : _items[_i]);

  /// What the hero is showing, for a flag: the movie, and — if its trailer is
  /// on screen — which cached trailer and how far into it.
  Map<String, Object?> flagInfo() {
    final m = current;
    return {
      'hero_movie_id': m?.id,
      'hero_movie_title': m?.title,
      'hero_fullscreen': _full,
      if (_trailerShown && m != null) ...{
        'kind': 'trailer',
        'movie_id': m.id,
        'movie_title': m.title,
        'position_seconds': _trailer.positionSeconds,
        'trailer_url': m.trailerUrl,
      },
    };
  }

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
          if (mounted && d.logo != null) {
            setState(() {
              _logos[movie.id] = d.logo;
              _logoSubs[movie.id] = d.logoSubtitle;
            });
          }
        }).catchError((_) {});
      }
    });
  }

  String? _logoFor(Movie m) => m.logo ?? _logos[m.id];
  String? _logoSubFor(Movie m) =>
      m.logo != null ? m.logoSubtitle : _logoSubs[m.id];

  @override
  void initState() {
    super.initState();
    _items = [...widget.featured]..shuffle(Random());
    _routePoll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _hold) return;
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
    unawaited(_reel.dispose());
    super.dispose();
  }

  void _showItem() {
    if (_items.isEmpty || !mounted) return;
    _stopTrailer();
    setState(() {});
    _dwell?.cancel();
    final m = current;
    if (m != null) _precacheLogo(m);
    // The backdrop + logo sit for a beat while the trailer loads; the reel
    // gets a longer one (it then dips to black into native video).
    final beat = _reelMode ? 2000 : 1400;
    if (_follow != null) {
      // Browsing the rails: the followed movie stays; only its trailer resumes.
      _trailerDelay?.cancel();
      if (!_suspended && _trailer.supported) {
        _trailerDelay = Timer(Duration(milliseconds: beat), _playTrailer);
      }
      return;
    }
    _dwell = Timer(Duration(seconds: _full ? 15 : 25), () => advance(1));
    _trailerDelay?.cancel();
    if (!_suspended && _trailer.supported) {
      _trailerDelay = Timer(Duration(milliseconds: beat), _playTrailer);
    }
    // No trailer to play: never leave a held black screen up.
    if (!_hasTrailer(m)) _releaseBlack();
  }

  bool _hasTrailer(Movie? m) =>
      m != null && m.trailerReady && m.trailerUrl != null;

  /// Lift the fader if a reel transition left it holding black.
  void _releaseBlack() {
    if (!mounted || !_faderOpaque) return;
    if (_fading) {
      // A fade is mid-flight — lifting now would fight it. Try again after.
      Timer(const Duration(milliseconds: 350), _releaseBlack);
      return;
    }
    setState(() => _faderOpaque = false);
  }

  /// Warm the logo so the reel's overlay capture never catches it unloaded.
  void _precacheLogo(Movie m) {
    final l = _logoFor(m);
    if (l != null && l.isNotEmpty && mounted) {
      precacheImage(NetworkImage(l), context).catchError((_) {});
    }
  }

  void _playTrailer({double start = 0}) {
    final m = current;
    if (_suspended || !mounted || m == null) return;
    // Only trailers already cached server-side — never wait on a download.
    if (!_hasTrailer(m)) return;
    if (_follow != null && _follow!.id != m.id) return;
    final url = '${widget.baseUrl}${m.trailerUrl}';
    if (_reelMode) {
      final req = ++_reelReq;
      _reel
          .play(url,
              start: start,
              overlay: () => _captureOverlay(m.id),
              beforeShow: () async {
                // Backdrop → black; mpv then fades in from black with the
                // logo already on. (Already black: skip.)
                if (!mounted || _faderOpaque) return;
                setState(() => _faderOpaque = true);
                await Future<void>.delayed(const Duration(milliseconds: 320));
              })
          .then((ok) {
            if (req != _reelReq || !mounted) return; // superseded
            // The fader is under the video now (or the play failed) — lift it.
            _releaseBlack();
            if (ok) {
              _dwell?.cancel(); // fullscreen: the trailer plays out
            } else if (_full && current?.id == m.id) {
              // mpv couldn't play it: the texture player, never a dead screen.
              _trailer.open(url, muted: false, start: start);
            }
          });
      return;
    }
    _trailer.open(url, muted: !_full, start: start);
  }

  /// The fullscreen scrim + logo + ratings as a window-sized bitmap for mpv
  /// (nothing Flutter draws can sit above native video). Waits for the logo
  /// to load and the home ↔ fullscreen slide to finish, so it matches what
  /// Flutter shows exactly.
  Future<ReelOverlay?> _captureOverlay(int movieId) async {
    final m = current;
    final l = m == null ? null : _logoFor(m);
    if (l != null && l.isNotEmpty) {
      try {
        await precacheImage(NetworkImage(l), context)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    final wait = _layoutSettled.difference(DateTime.now());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (!mounted) return null;
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || current?.id != movieId) return null;
    final box =
        _overlayKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (box == null || !box.hasSize) return null;
    final physical = View.of(context).physicalSize;
    final img = await box.toImage(pixelRatio: physical.width / box.size.width);
    try {
      final data = await img.toByteData(); // rawRgba = premultiplied
      return data == null ? null : ReelOverlay(data, img.width, img.height);
    } finally {
      img.dispose();
    }
  }

  void _onTrailerFrames() {
    if (!mounted) return;
    setState(() => _trailerShown = true);
    _dwell?.cancel();
    // Leaving fullscreen: "first frame" fires as the seek lands, a beat
    // before the picture is drawn — give it that beat before mpv steps aside.
    if (_exitPending) {
      Timer(const Duration(milliseconds: 250), () {
        if (_exitPending) _finishExit();
      });
    }
    if (!_full) {
      // Idle: a 25s cap from playback start; fullscreen lets it play out.
      _dwell = Timer(const Duration(seconds: 25), () => advance(1));
      // Get the reel's mpv up (paused, hidden) while home plays, so going
      // fullscreen never waits on a process launch.
      final m = current;
      if (_reel.supported && m != null && m.trailerUrl != null) {
        unawaited(_reel.warm('${widget.baseUrl}${m.trailerUrl}'));
      }
    }
  }

  /// Home is about to open a page (or a dialog) over big picture. The reel
  /// fades to black first (native video sits above every Flutter widget, so
  /// it must be gone before anything opens). Then take the trailer's video
  /// texture out of the tree — no frame may draw a texture that's being torn
  /// down (opening a franchise page mid-trailer-swap crashed the Windows
  /// engine in Skia's GrDirectContext::flush, 2026-09-26) — stop the players,
  /// and hold until [resumeAfterPage].
  Future<void> pauseForPage() async {
    _hold = true;
    _suspended = true;
    _exitPending = false;
    _dwell?.cancel();
    _trailerDelay?.cancel();
    _followDebounce?.cancel();
    if (_reel.showing) {
      if (mounted) setState(() => _faderOpaque = true);
      await _reel.fadeOut();
    }
    _reelReq++;
    await _reel.hide();
    if (mounted && _trailerShown) setState(() => _trailerShown = false);
    await WidgetsBinding.instance.endOfFrame;
    await _trailer.stop();
  }

  /// The page home opened is closed: back to the item — straight into its
  /// trailer in the fullscreen reel (still black), else backdrop + the beat.
  void resumeAfterPage() {
    if (!mounted) return;
    _hold = false;
    _suspended = false;
    _releaseBlack(); // back to the backdrop; the trailer follows the beat
    _showItem();
  }

  void _stopTrailer() {
    _trailerDelay?.cancel();
    _trailer.stop();
    _reelReq++;
    _reel.hide();
    if (mounted && _trailerShown) setState(() => _trailerShown = false);
  }

  /// Fade to black, run [swap] under the cover, fade back — the Roku fader.
  /// [holdBlack]: stay black after the swap; the reel lifts it once its video
  /// is up (or [_showItem] does, if there's no trailer after all).
  void _fadeThrough(VoidCallback swap, {bool holdBlack = false}) {
    if (_fading || !mounted) return;
    _fading = true;
    setState(() => _faderOpaque = true);
    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      swap();
      if (!holdBlack) setState(() => _faderOpaque = false);
      Timer(const Duration(milliseconds: 300), () => _fading = false);
    });
  }

  /// Next/previous featured movie (Left/Right on the hero, or the timer).
  void advance(int dir) {
    if (_follow != null) return; // browsing the rails: no rotation
    if (_items.length < 2 || _fading) return;
    // mpv fades to black with the app's fader beneath it; then the next
    // movie's backdrop + logo sit while its trailer loads.
    unawaited(_reel.fadeOut());
    _fadeThrough(() {
      _i = (_i + dir + _items.length) % _items.length;
      _showItem();
    });
  }

  void _setFullscreen(bool full) {
    if (!_reel.supported) {
      // Texture everywhere: one player, just unmute (Roku parity).
      _trailer.setMuted(!full);
      _fadeThrough(() {
        _full = full;
        _dwell?.cancel();
        if (!(_full && _trailerShown)) {
          _dwell = Timer(Duration(seconds: _trailerShown || !_full ? 25 : 15),
              () => advance(1));
        }
      });
      return;
    }
    // Windows: home = texture, fullscreen = native reel. No black either
    // way: the layout slides (rails out, logo cluster down, picture to
    // centre) while the texture keeps playing, and mpv takes over on the
    // exact frame with the logo already on it. Leaving is the reverse.
    _layoutSettled = DateTime.now().add(_slide);
    final m = current;
    if (full) {
      _exitPending = false;
      setState(() => _full = true);
      _dwell?.cancel();
      // Fallback advance only while nothing plays (a trailer plays out).
      if (!_trailerShown) {
        _dwell = Timer(const Duration(seconds: 15), () => advance(1));
      }
      if (_trailerShown && _hasTrailer(m)) {
        _trailer.setMuted(false); // sound now; mpv takes it over
        final req = ++_reelReq;
        _reel
            .handoff('${widget.baseUrl}${m!.trailerUrl}',
                sourcePos: () => _trailer.positionSeconds,
                overlay: () => _captureOverlay(m.id))
            .then((ok) {
          if (req != _reelReq || !mounted) return;
          if (ok) {
            _dwell?.cancel(); // the trailer plays out
            _trailer.stop();
            setState(() => _trailerShown = false);
          }
          // Not ok: the texture just keeps playing fullscreen.
        });
      }
      return;
    }
    // Leaving: get the texture running under mpv at mpv's position, then
    // step mpv aside and slide back (see [_finishExit]).
    if (_reel.showing && _hasTrailer(m)) {
      _exitPending = true;
      _trailer.open('${widget.baseUrl}${m!.trailerUrl}',
          muted: true, start: _reel.positionSeconds + 0.3);
      // Never hang on it: if the texture doesn't start, leave anyway.
      Timer(const Duration(seconds: 3), () {
        if (_exitPending) _finishExit();
      });
      return;
    }
    _trailer.setMuted(true);
    _reelReq++;
    _reel.hide();
    setState(() => _full = false);
    _dwell?.cancel();
    _dwell = Timer(const Duration(seconds: 25), () => advance(1));
  }

  /// Second half of leaving fullscreen: the texture is showing under the
  /// native video — hide mpv (same picture underneath) and slide home.
  void _finishExit() {
    if (!mounted) return;
    _exitPending = false;
    _layoutSettled = DateTime.now().add(_slide);
    _reelReq++;
    _reel.hide();
    setState(() => _full = false);
    _dwell?.cancel();
    _dwell = Timer(const Duration(seconds: 25), () => advance(1));
  }

  @override
  Widget build(BuildContext context) {
    final m = current;
    if (m == null) return const ColoredBox(color: NasColors.bg);
    final video = _trailerShown ? _trailer.view(fit: BoxFit.contain) : null;
    final shift = _full ? 0.0 : (m.trailerBars?.top ?? 0) * 1080;
    const curve = Curves.easeInOutCubic;

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
          // Home lifts a letterboxed picture to the top edge; fullscreen
          // centres it — slide between the two.
          TweenAnimationBuilder<double>(
            tween: Tween(end: shift),
            duration: _slide,
            curve: curve,
            builder: (_, dy, child) =>
                Transform.translate(offset: Offset(0, -dy), child: child),
            child: video,
          ),
        ],
        // Scrim + info: both layouts always built, cross-sliding on the
        // home ↔ fullscreen switch (home drifts down and out, the compact
        // fullscreen cluster settles down into place). This boundary is
        // also what the native reel gets as its overlay bitmap.
        RepaintBoundary(
          key: _overlayKey,
          child: Stack(fit: StackFit.expand, children: [
            AnimatedOpacity(
                duration: _slide,
                curve: curve,
                opacity: _full ? 0 : 1,
                child: const _HomeScrim()),
            AnimatedOpacity(
                duration: _slide,
                curve: curve,
                opacity: _full ? 1 : 0,
                child: const _FullscreenScrim()),
            Positioned(
              left: 90,
              top: 110,
              child: AnimatedSlide(
                duration: _slide,
                curve: curve,
                offset: _full ? const Offset(0, 0.35) : Offset.zero,
                child: AnimatedOpacity(
                  duration: _slide,
                  curve: curve,
                  opacity: _full ? 0 : 1,
                  child: _Info(
                    movie: m,
                    logo: _logoFor(m),
                    logoSubtitle: _logoSubFor(m),
                    compact: false,
                    dots: _follow == null && _items.length > 1
                        ? _Dots(count: _items.length, index: _i)
                        : null,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 90,
              bottom: 70,
              child: AnimatedSlide(
                duration: _slide,
                curve: curve,
                offset: _full ? Offset.zero : const Offset(0, -0.6),
                child: AnimatedOpacity(
                  duration: _slide,
                  curve: curve,
                  opacity: _full ? 1 : 0,
                  child: _Info(
                      movie: m,
                      logo: _logoFor(m),
                      logoSubtitle: _logoSubFor(m),
                      compact: true),
                ),
              ),
            ),
          ]),
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
      {required this.movie,
      required this.compact,
      this.logo,
      this.logoSubtitle,
      this.dots});

  final Movie movie;
  final String? logo;
  final String? logoSubtitle;
  final bool compact;
  final Widget? dots;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // Fullscreen: logo centred over the rating row.
      return bpLogoOver(
          logo: _logoOrTitle(centered: true),
          below: bpMetaRow(movie),
          maxWidth: 620);
    }
    final overview = movie.overview ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo centred over the rating row (house rule); overview stays left.
        bpLogoOver(
            logo: _logoOrTitle(centered: true),
            below: bpMetaRow(movie),
            maxWidth: 760),
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

  Widget _logoOrTitle({bool centered = false}) {
    final title = Align(
      alignment: centered ? Alignment.bottomCenter : Alignment.bottomLeft,
      child: Text(
        movie.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: centered ? TextAlign.center : TextAlign.start,
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
    return bpLogo(logo, logoSubtitle, title, centered: centered);
  }
}

/// A logo centred over the line beneath it (rating row, pick summary …): the
/// block is as wide as the wider of the two and both centre in it, while the
/// block itself stays wherever the layout puts it. The house rule for every
/// logo that sits on a line of text — never a left-aligned logo on a row.
Widget bpLogoOver({
  required Widget logo,
  required Widget below,
  double logoHeight = 150,
  double gap = 22,
  double minWidth = 420,
  double maxWidth = 1000,
}) =>
    ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: logoHeight, child: logo),
            SizedBox(height: gap),
            Center(child: below),
          ],
        ),
      ),
    );

/// A clearlogo — with this movie's subtitle under it (gold) when the logo is
/// the franchise's shared wordmark, so a sequel still reads as itself
/// ("THE LAND BEFORE TIME" / "VIII · The Big Freeze").
Widget bpLogo(String logo, String? subtitle, Widget fallback,
    {double subtitleSize = 34, bool centered = false}) {
  final image = Image.network(
    logo,
    fit: BoxFit.contain,
    alignment: centered ? Alignment.bottomCenter : Alignment.bottomLeft,
    errorBuilder: (_, _, _) => fallback,
  );
  if (subtitle == null || subtitle.isEmpty) return image;
  return Column(
    crossAxisAlignment:
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
    children: [
      Expanded(child: image),
      const SizedBox(height: 6),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: NasColors.amber,
          fontSize: subtitleSize,
          fontWeight: FontWeight.w800,
          height: 1.1,
          shadows: const [Shadow(blurRadius: 12, color: Colors.black87)],
        ),
      ),
    ],
  );
}

/// Year · IMDb · RT · quality, sized for the couch (matches the Roku meta row).
Widget bpMetaRow(Movie m) {
  const text = TextStyle(
      color: NasColors.text, fontSize: 30, fontWeight: FontWeight.w700);
  final parts = <Widget>[
    if (m.year != null) Text('${m.year}', style: text),
    // Content rating in an outlined box, like the TV's own ratings bug.
    if ((m.certification ?? '').isNotEmpty)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: NasColors.text, width: 2),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(m.certification!,
            style: const TextStyle(
                color: NasColors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
      ),
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
