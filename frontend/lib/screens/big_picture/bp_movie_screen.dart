import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cast_member.dart';
import '../../models/extra.dart';
import '../../models/franchise.dart';
import '../../models/movie.dart';
import '../../models/movie_file.dart';
import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../services/hdr_prefs.dart';
import '../../theme/app_theme.dart';
import '../hero_trailer.dart';
import '../player/player_view.dart';
import '../player_screen.dart';
import 'bp_hero.dart' show bpLogo, bpLogoOver, bpMetaRow;
import 'bp_read_more.dart';
import 'bp_track_picker.dart';
import '../../widgets/pad_hints.dart';

/// Big picture's movie page — the Netflix treatment, on the same fixed
/// 1920x1080 canvas as the home: full backdrop, logo, ratings, overview, big
/// Play/Resume + Trailer buttons, and the movie's extras as a rail.
///
/// Same one-model navigation as home: Left/Right move along the buttons or
/// the extras, Up/Down switch between them, A/Enter select, B/Esc back.
/// (The desktop page's edit pencils stay on the desktop page.)
class BpMovieScreen extends StatefulWidget {
  const BpMovieScreen({super.key, required this.movie, required this.baseUrl});

  final Movie movie;
  final String baseUrl;

  @override
  State<BpMovieScreen> createState() => _BpMovieScreenState();
}

enum _Row { overview, buttons, series, more, cast, extras }

class _BpMovieScreenState extends State<BpMovieScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  final _focus = FocusNode(debugLabel: 'bp-movie');

  List<MovieFile> _files = const [];
  List<Extra> _extras = const [];
  String? _logo;
  String? _logoSub;
  bool _loaded = false;
  TrackPick? _pick; // version + audio + subtitles Play will use
  Franchise? _series; // "More in this series" (includes this movie)
  int _seriesIdx = 0;
  List<Movie> _more = const []; // "More like this" (library only)
  int _moreIdx = 0;
  List<CastMember> _cast = const [];
  int _castIdx = 0;
  bool _inList = false; // on My List

  _Row _row = _Row.buttons;
  int _button = 0;
  int _extra = 0;

  Movie get _m => widget.movie;
  bool get _resume => (_m.progress ?? 0) > 0.01;

  @override
  void initState() {
    super.initState();
    _logo = _m.logo;
    _logoSub = _m.logoSubtitle;
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-movie', widget.baseUrl,
        () => {'movie_id': _m.id, 'movie_title': _m.title});
    _load();
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.getMovieDetail(_m.id);
      if (!mounted) return;
      setState(() {
        _files = d.files;
        _extras = d.extras;
        if (_logo == null) {
          _logo = d.logo;
          _logoSub = d.logoSubtitle;
        }
        _series = d.series;
        _inList = d.inWatchlist;
        final here = d.series?.movies.indexWhere((m) => m.id == _m.id) ?? -1;
        _seriesIdx = here < 0 ? 0 : here;
        _loaded = true;
      });
      final pick = await TrackPick.load(_m.id, d.files);
      if (mounted) setState(() => _pick = pick);
      final rel = await _api.getRelated(_m.id);
      if (mounted) {
        setState(() {
          _more = rel.moreLikeThis;
          _cast = rel.cast;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  // Buttons: Play/Resume, Trailer, Versions & Audio, My List.
  static const _buttonCount = 4;

  bool get _hasSeries => (_series?.movies.length ?? 0) > 1;

  /// The rows ↓/↑ step through, in order — only the ones that have content.
  List<_Row> get _rows => [
        if ((_m.overview ?? '').isNotEmpty) _Row.overview, // ▲ from the buttons
        _Row.buttons,
        if (_hasSeries) _Row.series,
        if (_more.isNotEmpty) _Row.more,
        if (_cast.isNotEmpty) _Row.cast,
        if (_extras.isNotEmpty) _Row.extras,
      ];

  /// What the bottom band shows: the row you're on, or (on the buttons) the
  /// first one below them.
  _Row? get _bandRow {
    if (_row != _Row.buttons && _row != _Row.overview) return _row;
    final rows = _rows;
    final i = rows.indexOf(_Row.buttons);
    return i + 1 < rows.length ? rows[i + 1] : null;
  }

  void _move(int dx, int dy) {
    setState(() {
      if (dy != 0) {
        final rows = _rows;
        final i = rows.indexOf(_row).clamp(0, rows.length - 1);
        _row = rows[(i + dy).clamp(0, rows.length - 1)];
        return;
      }
      switch (_row) {
        case _Row.overview:
          break;
        case _Row.buttons:
          _button = (_button + dx).clamp(0, _buttonCount - 1);
        case _Row.series:
          _seriesIdx = (_seriesIdx + dx).clamp(0, _series!.movies.length - 1);
        case _Row.more:
          _moreIdx = (_moreIdx + dx).clamp(0, _more.length - 1);
        case _Row.cast:
          _castIdx = (_castIdx + dx).clamp(0, _cast.length - 1);
        case _Row.extras:
          _extra = (_extra + dx).clamp(0, _extras.length - 1);
      }
    });
  }

  void _readMore() => showBpReadMore(context,
      title: _m.title,
      subtitle: [
        if (_m.year != null) '${_m.year}',
        if (_m.runtimeLabel != null) _m.runtimeLabel!,
        ..._m.genres.take(3),
      ].join('  ·  '),
      text: _m.overview ?? '');

  void _activate() {
    if (_row == _Row.overview) {
      _readMore();
      return;
    }
    if (_row == _Row.series && _hasSeries) {
      final m = _series!.movies[_seriesIdx];
      if (m.id != _m.id) {
        _open(BpMovieScreen(movie: m, baseUrl: widget.baseUrl));
      }
    } else if (_row == _Row.more && _more.isNotEmpty) {
      _open(BpMovieScreen(movie: _more[_moreIdx], baseUrl: widget.baseUrl));
    } else if (_row == _Row.cast) {
      // Browsing only (an actor page is a later idea).
    } else if (_row == _Row.extras && _extras.isNotEmpty) {
      final e = _extras[_extra];
      _open(PlayerScreen(fileId: e.id, baseUrl: widget.baseUrl, title: e.title));
    } else if (_button == 0) {
      _play();
    } else if (_button == 2) {
      _openPicker();
    } else if (_button == 3) {
      _toggleList();
    } else {
      _open(_BpTrailerScreen(
        url: '${widget.baseUrl}/api/movies/${_m.id}/trailer',
        baseUrl: widget.baseUrl,
        movie: _m,
      ));
    }
  }

  void _play() {
    if (_files.isEmpty) return; // still loading
    final pick = _pick ?? TrackPick(fileId: _files.first.id);
    unawaited(pick.save(_m.id));
    _open(PlayerScreen(
      fileId: pick.fileId,
      baseUrl: widget.baseUrl,
      title: _m.title,
      audioTrack: pick.audio,
      subtitleTrack: pick.subtitle,
      versions: _files,
      externalSubtitle: pick.external,
    ));
  }

  Future<void> _toggleList() async {
    final want = !_inList;
    setState(() => _inList = want); // instant; reverted if the server says no
    try {
      final now = await _api.setWatchlist(_m.id, want);
      if (!mounted) return;
      setState(() => _inList = now);
      FlagService.say(now ? 'Added to My List' : 'Removed from My List');
    } catch (_) {
      if (mounted) setState(() => _inList = !want);
      FlagService.say("Couldn't update My List");
    }
  }

  Future<void> _openPicker() async {
    final pick = _pick;
    if (pick == null || _files.isEmpty) return;
    final result = await Navigator.of(context).push<TrackPick>(
      MaterialPageRoute(
        builder: (_) => BpTrackPicker(
          title: _m.title,
          files: _files,
          initial: pick,
          baseUrl: widget.baseUrl,
          logo: _logo,
          logoSubtitle: _logoSub,
        ),
      ),
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (result != null) {
      setState(() => _pick = result);
      unawaited(result.save(_m.id));
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _focus.requestFocus();
  }

  bool _onPad(PadButton b) {
    if (!_focus.hasPrimaryFocus) return false;
    switch (b) {
      case PadButton.up:
        _move(0, -1);
      case PadButton.down:
        _move(0, 1);
      case PadButton.left:
        _move(-1, 0);
      case PadButton.right:
        _move(1, 0);
      case PadButton.a:
        _activate();
      case PadButton.b:
        Navigator.of(context).maybePop();
      default:
        return false;
    }
    return true;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _move(0, -1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _move(0, 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _move(-1, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _move(1, 0);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.select) {
      if (e is KeyDownEvent) _activate();
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.goBack) {
      if (e is KeyDownEvent) Navigator.of(context).maybePop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
    final backdrop = _m.backdropUrl(size: 'original');
    final overview = _m.overview ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NasColors.bg),
        if (backdrop != null)
          Image.network(backdrop,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink()),
        const _PageScrim(),
        Positioned(
          left: 90,
          top: 120,
          width: 1200, // 4 buttons (Play · Trailer · Versions & Audio · My List)
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo centred over the rating row (house rule).
              bpLogoOver(
                logo: _logoOrTitle(),
                below: bpMetaRow(_m),
                logoHeight: 180,
                gap: 26,
                maxWidth: 760,
              ),
              if (_m.genres.isNotEmpty || _m.runtimeLabel != null) ...[
                const SizedBox(height: 14),
                Text(
                  [
                    if (_m.runtimeLabel != null) _m.runtimeLabel!,
                    ..._m.genres.take(3),
                  ].join('  ·  '),
                  style: const TextStyle(color: NasColors.muted, fontSize: 26),
                ),
              ],
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 26),
                // ▲ from the buttons highlights it; A opens the whole text.
                bpOverviewFocus(
                  width: 900,
                  focused: _row == _Row.overview,
                  child: GestureDetector(
                    onTap: _readMore,
                    child: SizedBox(
                      width: 900,
                      child: Text(
                        overview,
                        // 3 lines (like the home hero): the column then always
                        // ends above the More in / More like this / Cast band.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFDDE2F5), fontSize: 28, height: 1.35),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              Row(children: [
                _BpButton(
                  icon: Icons.play_arrow_rounded,
                  label: _resume ? 'Resume' : 'Play',
                  primary: true,
                  focused: _row == _Row.buttons && _button == 0,
                  busy: !_loaded,
                  onTap: () {
                    setState(() {
                      _row = _Row.buttons;
                      _button = 0;
                    });
                    _play();
                  },
                ),
                const SizedBox(width: 24),
                _BpButton(
                  icon: Icons.movie_outlined,
                  label: 'Trailer',
                  focused: _row == _Row.buttons && _button == 1,
                  onTap: () {
                    setState(() {
                      _row = _Row.buttons;
                      _button = 1;
                    });
                    _activate();
                  },
                ),
                const SizedBox(width: 24),
                _BpButton(
                  icon: Icons.tune_rounded,
                  label: _files.length > 1 ? 'Versions & Audio' : 'Audio & Subtitles',
                  focused: _row == _Row.buttons && _button == 2,
                  onTap: () {
                    setState(() {
                      _row = _Row.buttons;
                      _button = 2;
                    });
                    _activate();
                  },
                ),
                const SizedBox(width: 24),
                _BpButton(
                  icon: _inList ? Icons.check_rounded : Icons.add_rounded,
                  label: '',
                  focused: _row == _Row.buttons && _button == 3,
                  onTap: () {
                    setState(() {
                      _row = _Row.buttons;
                      _button = 3;
                    });
                    _activate();
                  },
                ),
              ]),
              if (_row == _Row.buttons && _button == 3) ...[
                const SizedBox(height: 10),
                Text(_inList ? 'On My List — A to remove' : 'Add to My List',
                    style: const TextStyle(
                        color: NasColors.amber,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ],
              if (_pick != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: 1000,
                  child: Text(
                    _pick!.summary(_files),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: NasColors.muted,
                        fontSize: 24,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (_resume) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: 420,
                  height: 6,
                  child: ColoredBox(
                    color: Colors.white24,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _m.progress!,
                      child: const ColoredBox(color: NasColors.amber),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // One band at the bottom, showing the row you're on (series → more
        // like this → cast → extras).
        if (_bandRow == _Row.series)
          _seriesRail()
        else if (_bandRow == _Row.more)
          _moreRail()
        else if (_bandRow == _Row.cast)
          _castRail()
        else if (_bandRow == _Row.extras)
          _extrasRail(),
      ],
    );
  }

  Widget _logoOrTitle() {
    final title = Align(
      alignment: Alignment.bottomCenter,
      child: Text(
        _m.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.w800,
            height: 1.05),
      ),
    );
    final logo = _logo;
    if (logo == null || logo.isEmpty) return title;
    return bpLogo(logo, _logoSub, title, subtitleSize: 40, centered: true);
  }

  /// Extras along the bottom; the focused card stays in the left slot and the
  /// rail slides under it (same as the home rails).
  Widget _seriesRail() {
    const cardW = 320.0, cardH = 180.0, gap = 24.0;
    final ms = _series!.movies;
    final focused = _row == _Row.series;
    return Positioned(
      left: 0,
      right: 0,
      top: 800,
      height: 260,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 90,
            top: 0,
            child: Text('More in ${_series!.name}  ·  ${ms.length}',
                style: const TextStyle(
                    color: NasColors.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w600)),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 90 - (focused ? _seriesIdx : 0) * (cardW + gap),
            top: 56,
            child: Row(children: [
              for (int i = 0; i < ms.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _SeriesCard(
                  movie: ms[i],
                  width: cardW,
                  height: cardH,
                  current: ms[i].id == _m.id,
                  focused: focused && i == _seriesIdx,
                  onTap: () {
                    setState(() {
                      _row = _Row.series;
                      _seriesIdx = i;
                    });
                    _activate();
                  },
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _moreRail() {
    const cardW = 320.0, cardH = 180.0, gap = 24.0;
    final focused = _row == _Row.more;
    return _band(
      title: 'More like this',
      offset: (focused ? _moreIdx : 0) * (cardW + gap),
      children: [
        for (int i = 0; i < _more.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _SeriesCard(
            movie: _more[i],
            width: cardW,
            height: cardH,
            current: false,
            focused: focused && i == _moreIdx,
            onTap: () {
              setState(() {
                _row = _Row.more;
                _moreIdx = i;
              });
              _activate();
            },
          ),
        ],
      ],
    );
  }

  Widget _castRail() {
    const cardW = 170.0, gap = 22.0;
    final focused = _row == _Row.cast;
    return _band(
      title: 'Cast',
      offset: (focused ? _castIdx : 0) * (cardW + gap),
      children: [
        for (int i = 0; i < _cast.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _CastCard(member: _cast[i], width: cardW, focused: focused && i == _castIdx),
        ],
      ],
    );
  }

  /// A bottom-band rail: title + a row that slides so the focused card stays
  /// in the left slot.
  Widget _band({
    required String title,
    required double offset,
    required List<Widget> children,
  }) =>
      Positioned(
        left: 0,
        right: 0,
        top: 800,
        height: 260,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 90,
              top: 0,
              child: Text(title,
                  style: const TextStyle(
                      color: NasColors.text,
                      fontSize: 32,
                      fontWeight: FontWeight.w600)),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: 90 - offset,
              top: 56,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ],
        ),
      );

  Widget _extrasRail() {
    const cardW = 420.0, gap = 24.0;
    final focused = _row == _Row.extras;
    return Positioned(
      left: 0,
      right: 0,
      top: 800,
      height: 250,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 90,
            top: 0,
            child: Text('Extras  ·  ${_extras.length}',
                style: const TextStyle(
                    color: NasColors.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w600)),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 90 - _extra * (cardW + gap),
            top: 56,
            child: Row(children: [
              for (int i = 0; i < _extras.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _ExtraCard(
                  extra: _extras[i],
                  width: cardW,
                  focused: focused && i == _extra,
                  onTap: () {
                    setState(() {
                      _row = _Row.extras;
                      _extra = i;
                    });
                    _activate();
                  },
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _PageScrim extends StatelessWidget {
  const _PageScrim();

  @override
  Widget build(BuildContext context) {
    const navy = NasColors.bg;
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [navy.withValues(alpha: 0.95), navy.withValues(alpha: 0)],
              stops: const [0.0, 0.7],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [navy.withValues(alpha: 0), navy],
              stops: const [0.55, 1.0],
            ),
          ),
        ),
      ]),
    );
  }
}

class _BpButton extends StatelessWidget {
  const _BpButton({
    required this.icon,
    required this.label,
    required this.focused,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool focused;
  final bool primary;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? NasColors.amber
        : (focused ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = primary || focused ? NasColors.bg : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: focused ? 1.08 : 1.0,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: label.isEmpty ? 22 : 40, vertical: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: focused ? Colors.white : Colors.transparent, width: 4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            busy
                ? SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3, color: fg))
                : Icon(icon, color: fg, size: 40),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      color: fg, fontSize: 30, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A "More in this series" card: the movie's backdrop, title + year over it.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.movie,
    required this.width,
    required this.height,
    required this.current,
    required this.focused,
    required this.onTap,
  });

  final Movie movie;
  final double width;
  final double height;
  final bool current;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = movie.backdropUrl(size: 'w780');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: focused ? 1.07 : 1,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: NasColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: focused ? Colors.white : Colors.transparent, width: 4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xDD000000)],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (current)
                      const Text('NOW VIEWING',
                          style: TextStyle(
                              color: NasColors.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                    Text(movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    if (movie.year != null)
                      Text('${movie.year}',
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 18)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Cast card: round headshot, name, character.
class _CastCard extends StatelessWidget {
  const _CastCard(
      {required this.member, required this.width, required this.focused});

  final CastMember member;
  final double width;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final photo = member.photo;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 150),
            scale: focused ? 1.08 : 1,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NasColors.surface,
                border: Border.all(
                    color: focused ? Colors.white : Colors.transparent, width: 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: photo == null
                  ? const Icon(Icons.person, color: NasColors.muted, size: 64)
                  : Image.network(photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.person,
                          color: NasColors.muted, size: 64)),
            ),
          ),
          const SizedBox(height: 10),
          Text(member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: focused ? Colors.white : NasColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          if (member.character != null)
            Text(member.character!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: NasColors.muted, fontSize: 17)),
        ],
      ),
    );
  }
}

class _ExtraCard extends StatelessWidget {
  const _ExtraCard({
    required this.extra,
    required this.width,
    required this.focused,
    required this.onTap,
  });

  final Extra extra;
  final double width;
  final bool focused;
  final VoidCallback onTap;

  String? get _length {
    final d = extra.duration;
    if (d == null || d <= 0) return null;
    final m = (d / 60).round();
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m < 1 ? 1 : m} min';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: focused ? 1.05 : 1.0,
        child: Container(
          width: width,
          height: 150,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: NasColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: focused ? Colors.white : Colors.transparent, width: 4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(extra.type.toUpperCase(),
                  style: const TextStyle(
                      color: NasColors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(extra.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: NasColors.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.2)),
              const Spacer(),
              if (_length != null)
                Text(_length!,
                    style:
                        const TextStyle(color: NasColors.muted, fontSize: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A movie's trailer, fullscreen with sound, never cropped. B/Esc closes it;
/// it closes itself when the trailer ends or can't be played.
class _BpTrailerScreen extends StatefulWidget {
  const _BpTrailerScreen(
      {required this.url, required this.baseUrl, required this.movie});

  final String url;
  final String baseUrl;
  final Movie movie;

  @override
  State<_BpTrailerScreen> createState() => _BpTrailerScreenState();
}

class _BpTrailerScreenState extends State<_BpTrailerScreen> {
  final _focus = FocusNode(debugLabel: 'bp-trailer');
  // SDR: the in-app texture player, with our own controls drawn over it.
  // HDR (Windows, HDR wanted, trailer is HDR): native mpv — the movie
  // pipeline, the only one that shows HDR; its uosc UI is the controls.
  TrailerPlayer? _player;
  Widget? _native;
  Timer? _endPoll;
  Timer? _hide;
  Timer? _tick;
  bool _playing = false;
  bool _controls = true;

  bool get _hdr => _native != null;

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-trailer', widget.baseUrl, () => {
          'kind': 'trailer',
          'movie_id': widget.movie.id,
          'movie_title': widget.movie.title,
          'position_seconds':
              _hdr ? playerCurrentTime() : _player?.positionSeconds,
          'trailer_url': widget.url,
          'hdr': _hdr,
        });
    _start();
  }

  Future<void> _start() async {
    final wantHdr = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        await HdrPrefs.wantHdr();
    // Only an actually-HDR trailer goes to native mpv — spinning it up (and
    // the TV's signal switch) for an SDR trailer is just a glitch.
    var hdr = false;
    if (wantHdr) {
      try {
        final src =
            await ApiService(widget.baseUrl).getTrailerSource(widget.movie.id);
        hdr = src['hdr'] == true;
      } catch (_) {}
    }
    if (!mounted) return;
    if (hdr) {
      setDirectMedia(null); // the seam is shared with the movie player
      setStartPosition(0);
      setStartTracks(null, null);
      setState(() {
        _native = buildPlayerView('${widget.url}?variant=hdr', false);
        _playing = true;
      });
      // Show the title bar once it's up (the UI only appears on activity).
      Timer(const Duration(milliseconds: 1800), () {
        if (mounted) playerUosc('flash-top-bar');
      });
      _endPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final d = playerDuration();
        if (d > 0 && playerCurrentTime() >= d - 0.5) _close();
      });
    } else {
      _player = TrailerPlayer(
        onFirstFrame: () {
          if (!mounted) return;
          setState(() => _playing = true);
          _poke(); // controls up for a moment as it starts
        },
        onFinished: _close,
        onError: _close,
      );
      unawaited(_player!.open(widget.url, muted: false));
      // Progress bar + time refresh while the controls are showing.
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _controls) setState(() {});
      });
    }
  }

  /// Bring the controls up; they fade after 3 s unless paused.
  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_player?.paused == true) {
        _poke();
        return;
      }
      setState(() => _controls = false);
    });
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _endPoll?.cancel();
    _hide?.cancel();
    _tick?.cancel();
    _player?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _endPoll?.cancel();
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Every button is claimed here — nothing may fall through to the movie
  /// page underneath (which backed out of the trailer on any press).
  bool _onPad(PadButton b) {
    if (_hdr) {
      // Native player: the movie controls (A pause, ←/→ skip, menus…); B
      // leaves once no menu is open.
      if (!playerPad(b) && b == PadButton.b) _close();
      return true;
    }
    final p = _player;
    switch (b) {
      case PadButton.b:
        _close();
        return true;
      case PadButton.a:
        p?.togglePause();
      case PadButton.left:
        p?.seekBy(-10);
      case PadButton.right:
        p?.seekBy(10);
      default:
        break;
    }
    _poke();
    return true;
  }

  static String _fmt(double s) {
    final t = s.isFinite && s > 0 ? s.round() : 0;
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  Widget _overlay() {
    final p = _player;
    final pos = p?.positionSeconds ?? 0;
    final dur = p?.durationSeconds ?? 0;
    final paused = p?.paused ?? false;
    const shadow = [Shadow(blurRadius: 10, color: Colors.black)];
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          children: [
            if (paused)
              const Center(
                child: Icon(Icons.pause_circle_filled,
                    size: 140, color: Color(0xCCFFFFFF), shadows: shadow),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(64, 90, 64, 48),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${widget.movie.title} — Trailer',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            shadows: shadow)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(_fmt(pos),
                            style: const TextStyle(
                                color: NasColors.text,
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 20),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
                              minHeight: 8,
                              color: NasColors.amber,
                              backgroundColor: const Color(0x55FFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text('-${_fmt(dur - pos)}',
                            style: const TextStyle(
                                color: NasColors.text,
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const PadHints([
                      (PadGlyph.a, 'Pause'),
                      (PadGlyph.dpadHorizontal, 'Skip 10s'),
                      (PadGlyph.b, 'Back'),
                    ], size: 30, fontSize: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view =
        _native ?? (_playing ? _player?.view(fit: BoxFit.contain) : null);
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.backspace): _close,
          const SingleActivator(LogicalKeyboardKey.space): () {
            _player?.togglePause();
            _poke();
          },
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            _player?.seekBy(-10);
            _poke();
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            _player?.seekBy(10);
            _poke();
          },
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: MouseRegion(
            onHover: (_) => _poke(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                view ??
                    const Center(
                        child: CircularProgressIndicator(
                            color: NasColors.amber)),
                if (!_hdr && _playing) _overlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
