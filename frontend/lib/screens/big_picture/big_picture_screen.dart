import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home.dart';
import '../../models/movie.dart';
import '../../services/api_service.dart';
import '../../services/fullscreen.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../library_screen.dart';
import '../movie_detail_screen.dart';
import '../settings_screen.dart';
import 'bp_hero.dart';

/// Big picture mode: the 10-foot, fullscreen home for the couch PC, built to
/// match the Roku channel (the design source of truth). Everything is laid out
/// on a fixed 1920x1080 canvas and scaled to the screen, so positions and
/// sizes are the Roku's exactly.
///
/// Navigation is one model for keyboard now and the controller next: arrows
/// move, Enter/Space selects, Esc/Backspace goes back. Up from the first rail
/// focuses the hero (fullscreen, sound on); Back on home opens the menu.
class BigPictureScreen extends StatefulWidget {
  const BigPictureScreen({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<BigPictureScreen> createState() => _BigPictureScreenState();
}

enum _Zone { hero, rails }

// Rail geometry on the 1920x1080 canvas (Roku parity).
const double _railsTop = 540;
const double _railGap = 30;
const double _left = 90;
const double _titleH = 50;
const double _posterW = 200, _posterH = 300, _posterRow = 410;
const double _wideW = 480, _wideH = 270, _wideRow = 370;
const double _tileGap = 26;

class _BigPictureScreenState extends State<BigPictureScreen> {
  late final ApiService _api = ApiService(widget.baseUrl);
  final _focus = FocusNode(debugLabel: 'big-picture');
  final _heroKey = GlobalKey<BpHeroState>();

  HomeData? _data;
  Object? _error;
  List<HomeRail> _rails = const [];
  _Zone _zone = _Zone.rails;
  int _rail = 0;
  final Map<int, int> _item = {}; // rail index -> focused item index

  @override
  void initState() {
    super.initState();
    setFullscreen(true);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getHome();
      if (!mounted) return;
      setState(() {
        _data = data;
        _rails = data.rails.where((r) => r.movies.isNotEmpty).toList();
        _zone = _rails.isEmpty ? _Zone.hero : _Zone.rails;
      });
      _replayScriptedKeys();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate(widget.baseUrl);
    if (!mounted || info == null) return;
    await showDialog(
      context: context,
      builder: (_) => UpdateDialog(baseUrl: widget.baseUrl, info: info),
    );
    _focus.requestFocus();
  }

  /// Web preview only: `?bp=1&keys=down,down,right,up,back` replays those
  /// presses after load (one every 1.2 s), so layout and navigation can be
  /// checked from screenshots without typing into the browser.
  Future<void> _replayScriptedKeys() async {
    if (!kIsWeb) return;
    final keys = Uri.base.queryParameters['keys'];
    if (keys == null || keys.isEmpty) return;
    final actions = <String, VoidCallback>{
      'up': _up,
      'down': _down,
      'left': () => _sideways(-1),
      'right': () => _sideways(1),
      'enter': _select,
      'back': _back,
    };
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final k in keys.split(',')) {
      if (!mounted) return;
      actions[k.trim().toLowerCase()]?.call();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  bool _isWide(HomeRail r) =>
      r.movies.isNotEmpty && r.movies.first.resumePosition != null;

  double _rowHeight(HomeRail r) => _isWide(r) ? _wideRow : _posterRow;

  int _itemOf(int rail) => _item[rail] ?? 0;

  // ── Navigation ─────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _up();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _down();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _sideways(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _sideways(1);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.select) {
      if (e is KeyDownEvent) _select();
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.goBack) {
      if (e is KeyDownEvent) _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _up() {
    if (_zone == _Zone.hero) return;
    if (_rail == 0) {
      if (_data?.featured.isNotEmpty ?? false) setState(() => _zone = _Zone.hero);
    } else {
      setState(() => _rail--);
    }
  }

  void _down() {
    if (_zone == _Zone.hero) {
      if (_rails.isNotEmpty) setState(() => _zone = _Zone.rails);
    } else if (_rail < _rails.length - 1) {
      setState(() => _rail++);
    }
  }

  void _sideways(int dir) {
    if (_zone == _Zone.hero) {
      _heroKey.currentState?.advance(dir);
      return;
    }
    final n = _rails[_rail].movies.length;
    final next = (_itemOf(_rail) + dir).clamp(0, n - 1);
    if (next != _itemOf(_rail)) setState(() => _item[_rail] = next);
  }

  void _select() {
    if (_zone == _Zone.hero) {
      final m = _heroKey.currentState?.current;
      if (m != null) _openMovie(m);
    } else if (_rails.isNotEmpty) {
      _openMovie(_rails[_rail].movies[_itemOf(_rail)]);
    }
  }

  void _back() {
    if (_zone == _Zone.hero) {
      if (_rails.isNotEmpty) setState(() => _zone = _Zone.rails);
    } else if (_rail > 0) {
      setState(() => _rail = 0); // Back jumps to the top rail first
    } else {
      _openMenu();
    }
  }

  // Pushed pages aren't big picture screens yet: Esc/Backspace pops them so the
  // keyboard (and soon the controller) can always get back.
  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(ctx).maybePop(),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              Navigator.of(ctx).maybePop(),
        },
        child: Focus(autofocus: true, child: page),
      ),
    ));
    if (mounted) _focus.requestFocus();
  }

  void _openMovie(Movie m) =>
      _push(MovieDetailScreen(movie: m, baseUrl: widget.baseUrl));

  Future<void> _openMenu() async {
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => const _BpMenu(),
    );
    if (!mounted) return;
    switch (choice) {
      case 'exit':
        await setFullscreen(false);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => LibraryScreen(baseUrl: widget.baseUrl),
          settings: const RouteSettings(name: 'library'),
        ));
      case 'settings':
        await _push(const SettingsScreen());
      case 'quit':
        await quitApp();
      default:
        _focus.requestFocus();
    }
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

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
    if (_error != null) {
      return _message('Could not load the library:\n$_error');
    }
    final data = _data;
    if (data == null) {
      return const ColoredBox(
        color: NasColors.bg,
        child: Center(child: CircularProgressIndicator(color: NasColors.amber)),
      );
    }
    if (data.featured.isEmpty && _rails.isEmpty) {
      return _message('No movies yet — run a library scan on the server.');
    }
    final heroFocused = _zone == _Zone.hero;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NasColors.bg),
        if (data.featured.isNotEmpty)
          BpHero(
            key: _heroKey,
            featured: data.featured,
            baseUrl: widget.baseUrl,
            fullscreen: heroFocused,
          ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: heroFocused ? 0 : 1,
          child: IgnorePointer(ignoring: heroFocused, child: _railsLayer()),
        ),
      ],
    );
  }

  /// Rails from y=540. The focused rail always sits in that top slot and the
  /// rest scroll up under it (Roku fixedFocus); rails above it fade away so
  /// the hero info stays clean. Only a window of rails is built.
  Widget _railsLayer() {
    var offset = 0.0;
    for (int r = 0; r < _rail; r++) {
      offset += _rowHeight(_rails[r]) + _railGap;
    }
    final children = <Widget>[];
    var top = _railsTop - offset;
    for (int r = 0; r < _rails.length; r++) {
      final h = _rowHeight(_rails[r]);
      if (r >= _rail - 1 && r <= _rail + 2) {
        children.add(AnimatedPositioned(
          key: ValueKey('rail$r'),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: 0,
          width: 1920,
          top: top,
          height: h,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: r < _rail ? 0 : 1,
            child: _railRow(r),
          ),
        ));
      }
      top += h + _railGap;
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _railRow(int r) {
    final rail = _rails[r];
    final wide = _isWide(rail);
    final tileW = wide ? _wideW : _posterW;
    final focusedItem = _itemOf(r);
    final railFocused = _zone == _Zone.rails && r == _rail;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: _left,
          top: 0,
          child: Text(
            rail.title,
            style: const TextStyle(
              color: NasColors.text,
              fontSize: 32,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // The focused tile stays in the left slot; the row slides under it.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: _left - focusedItem * (tileW + _tileGap),
          top: _titleH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < rail.movies.length; i++) ...[
                if (i > 0) const SizedBox(width: _tileGap),
                _BpTile(
                  movie: rail.movies[i],
                  wide: wide,
                  focused: railFocused && i == focusedItem,
                  onTap: () {
                    setState(() {
                      _zone = _Zone.rails;
                      _rail = r;
                      _item[r] = i;
                    });
                    _openMovie(rail.movies[i]);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _message(String text) => ColoredBox(
        color: NasColors.bg,
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: NasColors.muted, fontSize: 32),
          ),
        ),
      );
}

/// A rail tile: 200x300 poster + two-line title, or (Continue Watching) a
/// 480x270 backdrop card with an amber progress bar + one-line title.
class _BpTile extends StatelessWidget {
  const _BpTile({
    required this.movie,
    required this.wide,
    required this.focused,
    required this.onTap,
  });

  final Movie movie;
  final bool wide;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = wide ? _wideW : _posterW;
    final h = wide ? _wideH : _posterH;
    final url = wide
        ? movie.backdropUrl(size: 'w780')
        : movie.posterUrl(size: 'w500');
    final progress = movie.progress;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: w,
        child: Column(
          crossAxisAlignment:
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: focused ? 1.06 : 1.0,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2046),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.transparent,
                    width: 4,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    if (wide && progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 8,
                        child: ColoredBox(
                          color: const Color(0xB0000000),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: const ColoredBox(color: NasColors.amber),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              movie.title,
              maxLines: wide ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: wide ? TextAlign.start : TextAlign.center,
              style: TextStyle(
                color: focused ? Colors.white : NasColors.text,
                fontSize: wide ? 28 : 22,
                fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back on home: leave big picture, open Settings, or quit.
class _BpMenu extends StatelessWidget {
  const _BpMenu();

  @override
  Widget build(BuildContext context) {
    Widget option(String value, IconData icon, String label,
            {bool autofocus = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextButton.icon(
            autofocus: autofocus,
            onPressed: () => Navigator.pop(context, value),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              foregroundColor: NasColors.text,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.focused)
                      ? NasColors.amber.withValues(alpha: 0.22)
                      : null),
            ),
            icon: Icon(icon, size: 26),
            label: Text(label, style: const TextStyle(fontSize: 20)),
          ),
        );
    return Dialog(
      backgroundColor: NasColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              option('exit', Icons.desktop_windows_outlined, 'Exit Big Picture',
                  autofocus: true),
              option('settings', Icons.settings_outlined, 'Settings'),
              option('quit', Icons.power_settings_new, 'Quit NASCinema'),
            ],
          ),
        ),
      ),
    );
  }
}
