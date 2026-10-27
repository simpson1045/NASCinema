import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie.dart';
import '../../models/show.dart';
import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../services/movie_search.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';
import 'bp_movie_screen.dart';
import 'bp_show_screen.dart';

/// Big Picture search: an on-screen keyboard (left) and results that fill in
/// as you type (right). Controller: D-pad moves (→ off the keyboard's edge
/// goes into the results, ← off their first column comes back), A types /
/// opens, X deletes, Y space, B back. A real keyboard types directly.
class BpSearchScreen extends StatefulWidget {
  const BpSearchScreen(
      {super.key, required this.baseUrl, this.initialLibrary, this.initialShows});

  final String baseUrl;
  // Tests hand the library in; normally it's fetched.
  final List<Movie>? initialLibrary;
  final List<Show>? initialShows;

  @override
  State<BpSearchScreen> createState() => _BpSearchScreenState();
}

enum _Zone { keys, results }

/// One search result: a movie or a TV show.
class _Hit {
  const _Hit.movie(Movie this.movie) : show = null;
  const _Hit.show(Show this.show) : movie = null;
  final Movie? movie;
  final Show? show;
  String get title => movie != null ? movie!.title : show!.title;
  int? get year => movie != null ? movie!.year : show!.year;
  String? get posterUrl => movie != null ? movie!.posterUrl() : show!.posterUrl();
}

class _BpSearchScreenState extends State<BpSearchScreen> {
  final _focus = FocusNode(debugLabel: 'bp-search');
  List<Movie> _library = const [];
  List<Show> _shows = const [];
  bool _loading = true;
  String _query = '';
  List<_Hit> _results = const [];

  _Zone _zone = _Zone.keys;
  int _key = 0; // index into _keys
  int _res = 0; // index into _results

  static const _cols = 6;
  static const _resCols = 4;
  static const _resRowsShown = 2;
  // A–Z, 0–9, then the action keys (each takes a full row slot pair).
  static final _keys = [
    for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
      String.fromCharCode(c),
    for (var d = 0; d <= 9; d++) '$d',
    'SPACE', 'DELETE', 'CLEAR',
  ];

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-search', widget.baseUrl,
        () => {'query': _query, 'results': _results.length});
    _load();
  }

  Future<void> _load() async {
    final api = ApiService(widget.baseUrl);
    final movies = widget.initialLibrary != null
        ? Future.value(widget.initialLibrary!)
        : api.listMovies();
    // TV shows too (MythBusters didn't come up, 2026-10-26).
    final shows = widget.initialShows != null || widget.initialLibrary != null
        ? Future.value(widget.initialShows ?? const <Show>[])
        : api.getShows();
    try {
      final lib = await movies;
      if (mounted) setState(() => _library = lib);
    } catch (_) {}
    try {
      final s = await shows;
      if (mounted) setState(() => _shows = s);
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      if (_query.isNotEmpty) _setQuery(_query);
    }
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    setState(() {
      _query = q;
      _results = _search(q);
      _res = 0;
      if (_results.isEmpty) _zone = _Zone.keys;
    });
  }

  /// Shows and movies ranked together: rank first, a show ahead of a movie
  /// on a tie, then the more popular movie.
  List<_Hit> _search(String q) {
    final scored = <(int, int, double, _Hit)>[
      for (final (r, s) in rankTitles(_shows, q, (s) => s.title)) (r, 0, 0.0, _Hit.show(s)),
      for (final (r, m) in rankTitles(_library, q, (m) => m.title, (m) => m.collectionName))
        (r, 1, -(m.popularity ?? 0), _Hit.movie(m)),
    ];
    scored.sort((a, b) => a.$1 != b.$1
        ? a.$1.compareTo(b.$1)
        : a.$2 != b.$2
            ? a.$2.compareTo(b.$2)
            : a.$3.compareTo(b.$3));
    return [for (final s in scored) s.$4];
  }

  void _typeKey(String k) {
    switch (k) {
      case 'SPACE':
        if (_query.isNotEmpty && !_query.endsWith(' ')) _setQuery('$_query ');
      case 'DELETE':
        if (_query.isNotEmpty) {
          _setQuery(_query.substring(0, _query.length - 1));
        }
      case 'CLEAR':
        _setQuery('');
      default:
        _setQuery('$_query${k.toLowerCase()}');
    }
  }

  Future<void> _open(_Hit h) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => h.movie != null
          ? BpMovieScreen(movie: h.movie!, baseUrl: widget.baseUrl)
          : BpShowScreen(baseUrl: widget.baseUrl, show: h.show!),
    ));
    if (mounted) _focus.requestFocus();
  }

  void _moveKeys(int dx, int dy) {
    final n = _keys.length;
    final row = _key ~/ _cols, col = _key % _cols;
    if (dx > 0 && (col == _cols - 1 || _key == n - 1)) {
      if (_results.isNotEmpty) {
        _zone = _Zone.results;
        _res = (row * _resCols).clamp(0, _results.length - 1) ~/ _resCols *
            _resCols;
        _res = _res.clamp(0, _results.length - 1);
      }
      return;
    }
    var next = _key + dx + dy * _cols;
    if (dy != 0) {
      // Up/down keep the column where the row allows it.
      next = next.clamp(0, n - 1);
    } else if (col + dx < 0) {
      return;
    }
    _key = next.clamp(0, n - 1);
  }

  void _moveResults(int dx, int dy) {
    final n = _results.length;
    final col = _res % _resCols;
    if (dx < 0 && col == 0) {
      _zone = _Zone.keys;
      _key = ((_res ~/ _resCols).clamp(0, (_keys.length - 1) ~/ _cols)) *
              _cols +
          _cols -
          1;
      _key = _key.clamp(0, _keys.length - 1);
      return;
    }
    final next = _res + dx + dy * _resCols;
    if (next >= 0 && next < n) _res = next;
  }

  bool _onPad(PadButton b) {
    setState(() {
      switch (b) {
        case PadButton.b:
          Navigator.of(context).maybePop();
        case PadButton.x:
          _typeKey('DELETE');
        case PadButton.y:
          _typeKey('SPACE');
        case PadButton.a:
          if (_zone == _Zone.keys) {
            _typeKey(_keys[_key]);
          } else if (_results.isNotEmpty) {
            _open(_results[_res]);
          }
        case PadButton.up:
        case PadButton.down:
        case PadButton.left:
        case PadButton.right:
          final dx = b == PadButton.left ? -1 : b == PadButton.right ? 1 : 0;
          final dy = b == PadButton.up ? -1 : b == PadButton.down ? 1 : 0;
          _zone == _Zone.keys ? _moveKeys(dx, dy) : _moveResults(dx, dy);
        default:
          break;
      }
    });
    return true; // the whole screen belongs to search
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final map = {
      LogicalKeyboardKey.arrowUp: PadButton.up,
      LogicalKeyboardKey.arrowDown: PadButton.down,
      LogicalKeyboardKey.arrowLeft: PadButton.left,
      LogicalKeyboardKey.arrowRight: PadButton.right,
      LogicalKeyboardKey.enter: PadButton.a,
      LogicalKeyboardKey.escape: PadButton.b,
    };
    if (map[k] != null) {
      _onPad(map[k]!);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _typeKey('DELETE');
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && RegExp(r"^[a-zA-Z0-9 &'\-:.]$").hasMatch(ch)) {
      _setQuery('$_query${ch.toLowerCase()}');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(90, 80, 90, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 640, child: _keyboard()),
                          const SizedBox(width: 70),
                          Expanded(child: _resultsPane()),
                        ],
                      ),
                    ),
                    const PadHints([
                      (PadGlyph.a, 'Select'),
                      (PadGlyph.x, 'Delete'),
                      (PadGlyph.y, 'Space'),
                      (PadGlyph.b, 'Back'),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyboard() {
    final keysFocused = _zone == _Zone.keys;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SEARCH',
            style: TextStyle(
                color: NasColors.amber,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const SizedBox(height: 14),
        Container(
          width: 640,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NasColors.amber, width: 2),
          ),
          child: Text(
            _query.isEmpty ? 'Type a movie or show…' : '$_query▏',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _query.isEmpty ? NasColors.muted : Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _keys.length; i++)
              _keyCap(_keys[i], focused: keysFocused && i == _key),
          ],
        ),
      ],
    );
  }

  Widget _keyCap(String k, {required bool focused}) {
    final action = k.length > 1;
    final label = switch (k) {
      'SPACE' => 'Space',
      'DELETE' => '⌫',
      'CLEAR' => 'Clear',
      _ => k,
    };
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: focused ? 1.12 : 1,
      child: Container(
        width: action ? 200 : 97,
        height: 82,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                color: focused ? NasColors.bg : Colors.white,
                fontSize: action ? 28 : 34,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _resultsPane() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: NasColors.amber));
    }
    if (_query.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Text('Start typing — movies, TV shows and series all work\n'
            '("potter", "jur park", "myth").',
            style: TextStyle(color: NasColors.muted, fontSize: 28, height: 1.5)),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Text('Nothing matches "$_query".',
            style: const TextStyle(color: NasColors.muted, fontSize: 28)),
      );
    }
    // Show the two rows around the focused result; the grid scrolls by rows.
    final row = _zone == _Zone.results ? _res ~/ _resCols : 0;
    final totalRows = (_results.length + _resCols - 1) ~/ _resCols;
    final firstRow = (row - (_resRowsShown - 1))
        .clamp(0, (totalRows - _resRowsShown).clamp(0, totalRows));
    final shown = _results.skip(firstRow * _resCols).take(_resRowsShown * _resCols);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_results.length} ${_results.length == 1 ? 'result' : 'results'}',
            style: const TextStyle(
                color: NasColors.amber,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 26,
          runSpacing: 22,
          children: [
            for (final (i, m) in shown.indexed)
              _poster(m,
                  focused: _zone == _Zone.results &&
                      firstRow * _resCols + i == _res),
          ],
        ),
        if ((firstRow + _resRowsShown) < totalRows)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('▼', style: TextStyle(color: NasColors.muted, fontSize: 22)),
          ),
      ],
    );
  }

  Widget _poster(_Hit m, {required bool focused}) {
    final url = m.posterUrl;
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: focused ? 1.07 : 1,
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 220,
              height: 330,
              decoration: BoxDecoration(
                color: NasColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: focused ? Colors.white : Colors.transparent, width: 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: url == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(m.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24)),
                      ),
                    )
                  : Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
            const SizedBox(height: 8),
            if (m.show != null)
              const Text('TV SHOW',
                  style: TextStyle(
                      color: NasColors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            Text(m.year != null ? '${m.title} (${m.year})' : m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: focused ? Colors.white : NasColors.muted,
                    fontSize: 22,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
