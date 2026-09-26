import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/extra.dart';
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
import 'bp_hero.dart' show bpLogo, bpMetaRow;

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

enum _Row { buttons, extras }

class _BpMovieScreenState extends State<BpMovieScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  final _focus = FocusNode(debugLabel: 'bp-movie');

  List<MovieFile> _files = const [];
  List<Extra> _extras = const [];
  String? _logo;
  String? _logoSub;
  bool _loaded = false;

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
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  // Buttons: Play/Resume, Trailer.
  static const _buttonCount = 2;

  void _move(int dx, int dy) {
    setState(() {
      if (dy > 0 && _row == _Row.buttons && _extras.isNotEmpty) {
        _row = _Row.extras;
      } else if (dy < 0 && _row == _Row.extras) {
        _row = _Row.buttons;
      } else if (dx != 0 && _row == _Row.buttons) {
        _button = (_button + dx).clamp(0, _buttonCount - 1);
      } else if (dx != 0 && _row == _Row.extras) {
        _extra = (_extra + dx).clamp(0, _extras.length - 1);
      }
    });
  }

  void _activate() {
    if (_row == _Row.extras && _extras.isNotEmpty) {
      final e = _extras[_extra];
      _open(PlayerScreen(fileId: e.id, baseUrl: widget.baseUrl, title: e.title));
    } else if (_button == 0) {
      _play();
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
    _open(PlayerScreen(
        fileId: _files.first.id, baseUrl: widget.baseUrl, title: _m.title));
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
          width: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 620, height: 180, child: _logoOrTitle()),
              const SizedBox(height: 26),
              bpMetaRow(_m),
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
                SizedBox(
                  width: 900,
                  child: Text(
                    overview,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFDDE2F5), fontSize: 28, height: 1.35),
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
              ]),
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
        if (_extras.isNotEmpty) _extrasRail(),
      ],
    );
  }

  Widget _logoOrTitle() {
    final title = Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        _m.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.w800,
            height: 1.05),
      ),
    );
    final logo = _logo;
    if (logo == null || logo.isEmpty) return title;
    return bpLogo(logo, _logoSub, title, subtitleSize: 40);
  }

  /// Extras along the bottom; the focused card stays in the left slot and the
  /// rail slides under it (same as the home rails).
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
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
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
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 30, fontWeight: FontWeight.w700)),
          ]),
        ),
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
  // SDR: the in-app texture player. HDR (Windows, HDR wanted): native mpv —
  // the same pipeline as the movies, the only one that shows HDR properly.
  TrailerPlayer? _player;
  Widget? _native;
  Timer? _endPoll;
  bool _playing = false;

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
        onFirstFrame: () => mounted ? setState(() => _playing = true) : null,
        onFinished: _close,
        onError: _close,
      );
      unawaited(_player!.open(widget.url, muted: false));
    }
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _endPoll?.cancel();
    _player?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _endPoll?.cancel();
    if (mounted) Navigator.of(context).maybePop();
  }

  bool _onPad(PadButton b) {
    if (_hdr) {
      // Native player: the movie controls (A pause, ←/→ skip, menus…);
      // B leaves once no menu is open. mpv's window holds OS focus here, so
      // don't gate on Flutter focus.
      if (playerPad(b)) return true;
      if (b == PadButton.b) {
        _close();
        return true;
      }
      return false;
    }
    if (!_focus.hasPrimaryFocus) return false;
    if (b == PadButton.b || b == PadButton.a) {
      _close();
      return true;
    }
    return false;
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
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: view ??
              const Center(
                  child: CircularProgressIndicator(color: NasColors.amber)),
        ),
      ),
    );
  }
}
