import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';

/// Track Manager, Phase A (docs/SPEC-track-manager.md): which foreign dubs and
/// subtitles a strip would remove across the library, biggest savings first.
/// A preview — nothing on disk changes yet.
class BpTrackManager extends StatefulWidget {
  const BpTrackManager({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<BpTrackManager> createState() => _BpTrackManagerState();
}

const _tabs = [
  ('strip', 'To strip'),
  ('protected', 'Protected'),
  ('no_english', 'No English audio'),
];

class _BpTrackManagerState extends State<BpTrackManager> {
  final _focus = FocusNode(debugLabel: 'bp-track-manager');
  Map<String, dynamic>? _plan;
  String? _error;
  int _tab = 0;
  int _cursor = 0;
  static const _visible = 6;

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-track-manager', widget.baseUrl,
        () => {'tab': _tabs[_tab].$1, 'cursor': _cursor});
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ApiService(widget.baseUrl).getTrackPlan();
      if (mounted) setState(() => _plan = p);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t load the plan ($e)');
    }
  }

  List<Map<String, dynamic>> get _rows =>
      ((_plan?[_tabs[_tab].$1] ?? const []) as List).cast<Map<String, dynamic>>();

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  void _setTab(int t) {
    if (t < 0 || t >= _tabs.length) return;
    setState(() {
      _tab = t;
      _cursor = 0;
    });
  }

  Future<void> _open() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BpTrackDetail(
          baseUrl: widget.baseUrl, fileId: (rows[_cursor]['file_id'] as num).toInt()),
    ));
    if (changed == true && mounted) _load();   // protect toggled: rows moved
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.a:
        _open();
      case PadButton.up:
        if (_cursor > 0) setState(() => _cursor--);
      case PadButton.down:
        if (_cursor < _rows.length - 1) setState(() => _cursor++);
      case PadButton.left || PadButton.lb:
        _setTab(_tab - 1);
      case PadButton.right || PadButton.rb:
        _setTab(_tab + 1);
      default:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NasColors.bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final b = {
            LogicalKeyboardKey.arrowUp: PadButton.up,
            LogicalKeyboardKey.arrowDown: PadButton.down,
            LogicalKeyboardKey.arrowLeft: PadButton.left,
            LogicalKeyboardKey.arrowRight: PadButton.right,
            LogicalKeyboardKey.enter: PadButton.a,
            LogicalKeyboardKey.escape: PadButton.b,
            LogicalKeyboardKey.backspace: PadButton.b,
          }[e.logicalKey];
          if (b == null) return KeyEventResult.ignored;
          _onPad(b);
          return KeyEventResult.handled;
        },
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(90, 70, 90, 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TRACK MANAGER',
                        style: TextStyle(
                            color: NasColors.amber,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                    const SizedBox(height: 10),
                    _header(),
                    const SizedBox(height: 26),
                    _tabBar(),
                    const SizedBox(height: 22),
                    Expanded(child: _body()),
                    PadHints([
                      (PadGlyph.dpadVertical, 'Move'),
                      (PadGlyph.dpadHorizontal, 'Tabs'),
                      (PadGlyph.a, 'Tracks'),
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

  Widget _header() {
    final t = (_plan?['totals'] ?? const {}) as Map;
    if (_plan == null) {
      return Text(_error ?? 'Reading the library…',
          style: const TextStyle(color: NasColors.muted, fontSize: 30));
    }
    final n = (t['strip'] ?? 0) as num;
    final fd = (t['foreign_default'] ?? 0) as num;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$n movies · ${fmtBytes((t['savings_bytes'] ?? 0) as num)} to reclaim',
            style: const TextStyle(
                color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            [
              if (fd > 0) '$fd start in a foreign language',
              '${t['protected'] ?? 0} protected',
              '${t['clean'] ?? 0} already clean',
            ].join('  ·  '),
            style: const TextStyle(color: NasColors.muted, fontSize: 24)),
        const SizedBox(height: 10),
        const Text('Preview — nothing on disk changes yet.',
            style: TextStyle(color: NasColors.violet, fontSize: 22)),
      ],
    );
  }

  Widget _tabBar() {
    return Row(children: [
      for (var i = 0; i < _tabs.length; i++)
        Container(
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: i == _tab ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
              '${_tabs[i].$2} (${((_plan?[_tabs[i].$1] ?? const []) as List).length})',
              style: TextStyle(
                  color: i == _tab ? NasColors.bg : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
        ),
    ]);
  }

  Widget _body() {
    if (_plan == null) return const SizedBox.shrink();
    final rows = _rows;
    if (rows.isEmpty) {
      return Text(
          _tab == 0 ? 'Nothing to strip — the library is clean.' : 'None.',
          style: const TextStyle(color: NasColors.muted, fontSize: 28));
    }
    final first = (_cursor - _visible ~/ 2)
        .clamp(0, (rows.length - _visible).clamp(0, rows.length));
    final shown = rows.skip(first).take(_visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          _row(shown[i], focused: first + i == _cursor),
        if (first + _visible < rows.length)
          Text('▼  ${rows.length - first - _visible} more',
              style: const TextStyle(color: NasColors.muted, fontSize: 20)),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r, {required bool focused}) {
    final fg = focused ? NasColors.bg : Colors.white;
    final sub = focused ? NasColors.bg.withValues(alpha: 0.75) : NasColors.muted;
    final dropped = ((r['dropped'] ?? const []) as List).cast<String>();
    final detail = r['protected'] != null
        ? r['protected'] as String
        : dropped.isEmpty
            ? ''
            : dropped.take(3).join('   ') +
                (dropped.length > 3 ? '   +${dropped.length - 3} more' : '');
    final poster = r['poster_path'] as String?;
    final year = r['year'] == null ? '' : ' (${r['year']})';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 24, 8),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 66,
              child: poster == null
                  ? Container(color: NasColors.surfaceRaised)
                  : Image.network('https://image.tmdb.org/t/p/w185$poster',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: NasColors.surfaceRaised)),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['title']}$year  ·  ${r['quality'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sub, fontSize: 19)),
              ],
            ),
          ),
          if (r['foreign_default'] == true) ...[
            const SizedBox(width: 16),
            _chip('Foreign default', NasColors.bad),
          ],
          if (r['status'] == 'strip') ...[
            const SizedBox(width: 22),
            Text(
                '${r['savings_partial'] == true ? '≥ ' : ''}'
                '${fmtBytes((r['savings_bytes'] ?? 0) as num)}',
                style: TextStyle(
                    color: focused ? NasColors.bg : NasColors.ok,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

/// One movie's tracks: keep/drop and why, which track plays first afterwards,
/// and the "Protect this movie" toggle (Y). Pops `true` if protection changed.
class BpTrackDetail extends StatefulWidget {
  const BpTrackDetail({super.key, required this.baseUrl, required this.fileId});

  final String baseUrl;
  final int fileId;

  @override
  State<BpTrackDetail> createState() => _BpTrackDetailState();
}

class _BpTrackDetailState extends State<BpTrackDetail> {
  final _focus = FocusNode(debugLabel: 'bp-track-detail');
  Map<String, dynamic>? _d;
  String? _error;
  bool _changed = false;
  bool _busy = false;
  int _first = 0;
  static const _visible = 11;

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-track-detail', widget.baseUrl,
        () => {'file_id': widget.fileId});
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService(widget.baseUrl).getTrackFile(widget.fileId);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t load this movie ($e)');
    }
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _streams =>
      ((_d?['streams'] ?? const []) as List).cast<Map<String, dynamic>>();

  Future<void> _toggleProtect() async {
    final d = _d;
    if (d == null || _busy) return;
    final on = d['manual_protect'] != true;
    setState(() => _busy = true);
    try {
      await ApiService(widget.baseUrl)
          .setTrackProtect((d['movie_id'] as num).toInt(), on);
      _changed = true;
      FlagService.say(on ? 'Protected — never stripped' : 'Protection removed');
      await _load();
    } catch (_) {
      FlagService.say('Couldn\'t change protection');
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).pop(_changed);
      case PadButton.y:
        _toggleProtect();
      case PadButton.up:
        if (_first > 0) setState(() => _first--);
      case PadButton.down:
        if (_first + _visible < _streams.length) setState(() => _first++);
      default:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: NasColors.bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final b = {
            LogicalKeyboardKey.arrowUp: PadButton.up,
            LogicalKeyboardKey.arrowDown: PadButton.down,
            LogicalKeyboardKey.keyP: PadButton.y,
            LogicalKeyboardKey.escape: PadButton.b,
            LogicalKeyboardKey.backspace: PadButton.b,
          }[e.logicalKey];
          if (b == null) return KeyEventResult.ignored;
          _onPad(b);
          return KeyEventResult.handled;
        },
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(90, 70, 90, 50),
                child: d == null
                    ? Text(_error ?? 'Loading…',
                        style: const TextStyle(color: NasColors.muted, fontSize: 30))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TRACKS',
                              style: TextStyle(
                                  color: NasColors.amber,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2)),
                          const SizedBox(height: 10),
                          Text(
                              '${d['title']}${d['year'] == null ? '' : ' (${d['year']})'}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 46,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(_summary(d),
                              style: const TextStyle(
                                  color: NasColors.muted, fontSize: 24)),
                          const SizedBox(height: 28),
                          Expanded(child: _list(d)),
                          PadHints([
                            (PadGlyph.dpadVertical, 'Scroll'),
                            (
                              PadGlyph.y,
                              d['manual_protect'] == true
                                  ? 'Remove protection'
                                  : 'Protect this movie'
                            ),
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

  String _summary(Map<String, dynamic> d) {
    final parts = <String>[
      if (d['quality'] != null) '${d['quality']}',
      if (d['size_bytes'] != null) fmtBytes(d['size_bytes'] as num),
    ];
    switch (d['status']) {
      case 'strip':
        parts.add('would save ${d['savings_partial'] == true ? 'at least ' : ''}'
            '${fmtBytes((d['savings_bytes'] ?? 0) as num)}');
      case 'protected':
        parts.add('${d['protected']} — never stripped');
      case 'no_english':
        parts.add('no English audio — skipped');
      default:
        parts.add('already clean — nothing to strip');
    }
    return parts.join('  ·  ');
  }

  Widget _list(Map<String, dynamic> d) {
    final streams = _streams;
    final newDefault = d['new_default_audio'];
    final shown = streams.skip(_first).take(_visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_first > 0)
          const Text('▲', style: TextStyle(color: NasColors.muted, fontSize: 20)),
        for (final s in shown)
          _streamRow(s,
              playsFirst: d['status'] == 'strip' && s['index'] == newDefault),
        if (_first + _visible < streams.length)
          Text('▼  ${streams.length - _first - _visible} more',
              style: const TextStyle(color: NasColors.muted, fontSize: 20)),
      ],
    );
  }

  Widget _streamRow(Map<String, dynamic> s, {required bool playsFirst}) {
    final keep = s['keep'] == true;
    final kind = s['kind'] as String? ?? '';
    final icon = switch (kind) {
      'video' => Icons.movie_outlined,
      'audio' => Icons.graphic_eq,
      _ => Icons.subtitles_outlined,
    };
    final est = s['est_bytes'] as num?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(18, 10, 24, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: keep ? 0.06 : 0.02),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: _chip(keep ? 'KEEP' : 'DROP', keep ? NasColors.ok : NasColors.bad)),
          Icon(icon, color: keep ? Colors.white : NasColors.muted, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text('${s['label'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: keep ? Colors.white : NasColors.muted,
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    decoration: keep ? null : TextDecoration.lineThrough,
                    decorationColor: NasColors.muted)),
          ),
          if (playsFirst) ...[
            _chip('PLAYS FIRST', NasColors.amber),
            const SizedBox(width: 16),
          ],
          SizedBox(
            width: 330,
            child: Text(s['why'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NasColors.muted, fontSize: 19)),
          ),
          SizedBox(
            width: 110,
            child: Text(est == null || kind == 'video' ? '' : fmtBytes(est),
                textAlign: TextAlign.right,
                style: const TextStyle(color: NasColors.muted, fontSize: 19)),
          ),
        ],
      ),
    );
  }
}

Widget _chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
    );

/// 70_100_000_000 -> "70.1 GB", 850_000_000 -> "850 MB".
String fmtBytes(num b) {
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
  if (b >= 1e6) return '${(b / 1e6).round()} MB';
  if (b >= 1e3) return '${(b / 1e3).round()} KB';
  return '${b.round()} B';
}
