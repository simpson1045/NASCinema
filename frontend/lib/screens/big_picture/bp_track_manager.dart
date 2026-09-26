import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';

/// Track Manager (docs/SPEC-track-manager.md): which foreign dubs and
/// subtitles to strip across the library, biggest savings first, and the
/// strips themselves. X strips a movie, Y strips all the worthwhile ones; the
/// Jobs tab follows them, undoes one (X) or frees the kept originals (Y).
/// Strips run on the server's strip worker; every original is kept until
/// "Confirm & free space".
class BpTrackManager extends StatefulWidget {
  const BpTrackManager({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<BpTrackManager> createState() => _BpTrackManagerState();
}

const _tabs = [
  ('strip', 'To strip'),
  ('jobs', 'Jobs'),
  ('protected', 'Protected'),
  ('no_english', 'No English audio'),
];

/// Same bar as the server's "Strip all": skip files where rewriting a whole
/// remux saves next to nothing, unless the movie starts in a foreign language.
const _stripAllMinBytes = 100000000;

class _BpTrackManagerState extends State<BpTrackManager> {
  final _focus = FocusNode(debugLabel: 'bp-track-manager');
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _jobs;
  String? _error;
  int _tab = 0;
  int _cursor = 0;
  Timer? _poll;
  String _jobsKey = '';
  // A question on screen (A = yes, B = no) before anything that commits.
  ({String text, Future<void> Function() yes})? _ask;
  static const _visible = 6;

  ApiService get _api => ApiService(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-track-manager', widget.baseUrl,
        () => {'tab': _tabs[_tab].$1, 'cursor': _cursor});
    _load();
    _loadJobs();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _loadJobs());
  }

  Future<void> _load() async {
    try {
      final p = await _api.getTrackPlan();
      if (mounted) setState(() => _plan = p);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t load the plan ($e)');
    }
  }

  Future<void> _loadJobs() async {
    try {
      final j = await _api.getStripJobs();
      if (!mounted) return;
      // A job changed state (finished, failed, undone…): the plan moved too.
      final key = ((j['jobs'] ?? const []) as List)
          .map((e) => '${e['id']}:${e['status']}:${e['request']}')
          .join(',');
      final changed = key != _jobsKey && _jobsKey.isNotEmpty;
      _jobsKey = key;
      setState(() => _jobs = j);
      if (changed) _load();
    } catch (_) {
      // Keep the last good state; the next tick retries.
    }
  }

  List<Map<String, dynamic>> get _rows {
    final key = _tabs[_tab].$1;
    final src = key == 'jobs' ? (_jobs?['jobs']) : (_plan?[key]);
    return ((src ?? const []) as List).cast<Map<String, dynamic>>();
  }

  Map<String, dynamic>? get _current {
    final rows = _rows;
    return rows.isEmpty ? null : rows[_cursor.clamp(0, rows.length - 1)];
  }

  Map get _totals => (_jobs?['totals'] ?? const {}) as Map;

  @override
  void dispose() {
    _poll?.cancel();
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
    final r = _current;
    if (r == null || _tabs[_tab].$1 == 'jobs') return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BpTrackDetail(
          baseUrl: widget.baseUrl, fileId: (r['file_id'] as num).toInt()),
    ));
    if (changed == true && mounted) {
      _load();
      _loadJobs();
    }
  }

  List<Map<String, dynamic>> get _worthwhile =>
      ((_plan?['strip'] ?? const []) as List)
          .cast<Map<String, dynamic>>()
          .where((r) =>
              r['job'] == null &&
              (((r['savings_bytes'] ?? 0) as num) >= _stripAllMinBytes ||
                  r['foreign_default'] == true))
          .toList();

  Future<void> _stripOne() async {
    final r = _current;
    if (r == null) return;
    if (r['job'] != null) {
      FlagService.say('Already ${(r['job'] as Map)['status']}');
      return;
    }
    try {
      final res = await _api.queueStrip([(r['file_id'] as num).toInt()]);
      FlagService.say(((res['queued'] ?? const []) as List).isNotEmpty
          ? 'Queued — ${r['title']}'
          : 'Not queued — it may already be clean');
    } catch (_) {
      FlagService.say('Couldn\'t queue it');
    }
    _load();
    _loadJobs();
  }

  void _askStripAll() {
    final rows = _worthwhile;
    if (rows.isEmpty) {
      FlagService.say('Nothing worth stripping right now');
      return;
    }
    final save = rows.fold<num>(0, (a, r) => a + ((r['savings_bytes'] ?? 0) as num));
    setState(() => _ask = (
          text: 'Strip ${rows.length} movie${rows.length == 1 ? '' : 's'} and save '
              'about ${fmtBytes(save)}?\n\nEach original is kept until you choose '
              'Confirm & free space on the Jobs tab.',
          yes: () async {
            await _api.queueStrip(null);
            FlagService.say('Queued ${rows.length} strips');
            _load();
            _loadJobs();
          },
        ));
  }

  void _jobAction() {
    final j = _current;
    if (j == null) return;
    final id = (j['id'] as num).toInt();
    if (j['status'] == 'queued') {
      _api.stripJobAction(id, 'cancel').then((_) {
        FlagService.say('Cancelled');
        _loadJobs();
      }, onError: (_) => FlagService.say('Couldn\'t cancel'));
    } else if (j['status'] == 'done' && j['request'] == null) {
      setState(() => _ask = (
            text: 'Put the original of ${j['title']} back?\n\n'
                'The stripped copy is discarded.',
            yes: () async {
              await _api.stripJobAction(id, 'undo');
              FlagService.say('Undoing — original coming back');
              _loadJobs();
            },
          ));
    }
  }

  void _askConfirm() {
    final n = (_totals['awaiting_confirm'] ?? 0) as num;
    if (n == 0) {
      FlagService.say('No kept originals to free');
      return;
    }
    final frees = (_totals['confirm_frees_bytes'] ?? 0) as num;
    setState(() => _ask = (
          text: 'Delete $n kept original${n == 1 ? '' : 's'} and free '
              '${fmtBytes(frees)}?\n\nThe stripped copies stay. This can\'t be undone.',
          yes: () async {
            await _api.confirmStrips(null);
            FlagService.say('Freeing ${fmtBytes(frees)}');
            _loadJobs();
          },
        ));
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final ask = _ask;
    if (ask != null) {
      if (b == PadButton.a) {
        setState(() => _ask = null);
        ask.yes().catchError((_) => FlagService.say('That didn\'t work — try again'));
      } else if (b == PadButton.b) {
        setState(() => _ask = null);
      }
      return true;
    }
    final tab = _tabs[_tab].$1;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.a:
        _open();
      case PadButton.x:
        if (tab == 'strip') _stripOne();
        if (tab == 'jobs') _jobAction();
      case PadButton.y:
        if (tab == 'strip') _askStripAll();
        if (tab == 'jobs') _askConfirm();
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

  List<(PadGlyph, String)> _hints() {
    final tab = _tabs[_tab].$1;
    final j = _current;
    return [
      (PadGlyph.dpadVertical, 'Move'),
      (PadGlyph.dpadHorizontal, 'Tabs'),
      if (tab != 'jobs') (PadGlyph.a, 'Tracks'),
      if (tab == 'strip') ...[
        (PadGlyph.x, 'Strip this'),
        (PadGlyph.y, 'Strip all'),
      ],
      if (tab == 'jobs' && j?['status'] == 'queued') (PadGlyph.x, 'Cancel'),
      if (tab == 'jobs' && j?['status'] == 'done' && j?['request'] == null)
        (PadGlyph.x, 'Undo'),
      if (tab == 'jobs' && ((_totals['awaiting_confirm'] ?? 0) as num) > 0)
        (PadGlyph.y, 'Confirm & free space'),
      (PadGlyph.b, 'Back'),
    ];
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
            LogicalKeyboardKey.keyX: PadButton.x,
            LogicalKeyboardKey.keyY: PadButton.y,
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
              child: Stack(
                children: [
                  Padding(
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
                        PadHints(_hints()),
                      ],
                    ),
                  ),
                  if (_ask != null) _askOverlay(_ask!.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _askOverlay(String text) => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          alignment: Alignment.center,
          child: Container(
            width: 980,
            padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
            decoration: BoxDecoration(
              color: NasColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NasColors.amber, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: const TextStyle(color: Colors.white, fontSize: 30, height: 1.35)),
                const SizedBox(height: 34),
                PadHints([(PadGlyph.a, 'Yes'), (PadGlyph.b, 'No')]),
              ],
            ),
          ),
        ),
      );

  String _workerLine() {
    final w = (_jobs?['worker'] ?? const {}) as Map;
    final t = _totals;
    final parts = <String>[];
    switch (w['state']) {
      case 'working':
        final running = ((_jobs?['jobs'] ?? const []) as List)
            .cast<Map<String, dynamic>>()
            .where((j) => j['status'] == 'running');
        parts.add(running.isEmpty
            ? 'Stripping…'
            : 'Stripping ${running.first['title']} — ${_pct(running.first)}');
      case 'waiting_for_load':
        parts.add('Strip worker waiting — the NAS is busy');
      case 'idle':
        parts.add('Strip worker ready');
      default:
        parts.add(_jobs == null ? 'Checking the strip worker…' : 'Strip worker offline');
    }
    final q = (t['queued'] ?? 0) as num;
    if (q > 0) parts.add('$q queued');
    final n = (t['awaiting_confirm'] ?? 0) as num;
    if (n > 0) {
      parts.add('$n stripped — ${fmtBytes((t['confirm_frees_bytes'] ?? 0) as num)} '
          'of originals kept (Jobs → Y to free)');
    }
    return parts.join('  ·  ');
  }

  String _pct(Map<String, dynamic> j) =>
      '${(((j['progress'] ?? 0) as num) * 100).round()}%';

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
        Text(_workerLine(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: NasColors.violet, fontSize: 22)),
      ],
    );
  }

  int _tabCount(String key) =>
      (((key == 'jobs' ? (_jobs?['jobs']) : (_plan?[key])) ?? const []) as List).length;

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
          child: Text('${_tabs[i].$2} (${_tabCount(_tabs[i].$1)})',
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
    final tab = _tabs[_tab].$1;
    if (rows.isEmpty) {
      return Text(
          switch (tab) {
            'strip' => 'Nothing to strip — the library is clean.',
            'jobs' => 'No strips yet. On To strip: X strips a movie, Y strips all.',
            _ => 'None.',
          },
          style: const TextStyle(color: NasColors.muted, fontSize: 28));
    }
    final cursor = _cursor.clamp(0, rows.length - 1);
    final first = (cursor - _visible ~/ 2)
        .clamp(0, (rows.length - _visible).clamp(0, rows.length));
    final shown = rows.skip(first).take(_visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          tab == 'jobs'
              ? _jobRow(shown[i], focused: first + i == cursor)
              : _row(shown[i], focused: first + i == cursor),
        if (first + _visible < rows.length)
          Text('▼  ${rows.length - first - _visible} more',
              style: const TextStyle(color: NasColors.muted, fontSize: 20)),
      ],
    );
  }

  Widget _card({required bool focused, required String? poster, required String title,
      required String detail, required List<Widget> trailing, double? progress}) {
    final fg = focused ? NasColors.bg : Colors.white;
    final sub = focused ? NasColors.bg.withValues(alpha: 0.75) : NasColors.muted;
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
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sub, fontSize: 19)),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        color: NasColors.amber,
                        backgroundColor: sub.withValues(alpha: 0.25)),
                  ),
                ],
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r, {required bool focused}) {
    final dropped = ((r['dropped'] ?? const []) as List).cast<String>();
    final detail = r['protected'] != null
        ? r['protected'] as String
        : dropped.isEmpty
            ? ''
            : dropped.take(3).join('   ') +
                (dropped.length > 3 ? '   +${dropped.length - 3} more' : '');
    final year = r['year'] == null ? '' : ' (${r['year']})';
    final job = r['job'] as Map?;
    return _card(
      focused: focused,
      poster: r['poster_path'] as String?,
      title: '${r['title']}$year  ·  ${r['quality'] ?? ''}',
      detail: detail,
      trailing: [
        if (job != null) ...[
          const SizedBox(width: 16),
          _chip(
              switch (job['status']) {
                'running' => 'STRIPPING ${(((job['progress'] ?? 0) as num) * 100).round()}%',
                'done' => 'STRIPPED',
                _ => 'QUEUED',
              },
              NasColors.amber),
        ],
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
    );
  }

  Widget _jobRow(Map<String, dynamic> j, {required bool focused}) {
    final status = j['status'] as String? ?? '';
    final err = j['error'] as String?;
    final req = j['request'] as String?;
    final orig = (j['original_bytes'] ?? 0) as num;
    final neu = j['new_bytes'] as num?;
    final waiting = ((_jobs?['worker'] ?? const {}) as Map)['state'] == 'waiting_for_load';
    final detail = req == 'undo'
        ? 'Undo requested…'
        : req == 'confirm'
            ? 'Freeing space…'
            : switch (status) {
                'queued' => waiting ? 'Queued — waiting for the NAS to calm down' : 'Queued',
                'running' => switch (j['phase']) {
                    'verifying' => 'Checking the new file…',
                    'placing' => 'Moving into place — ${_pct(j)}',
                    _ => 'Stripping — ${_pct(j)}',
                  },
                'done' => 'Done — original kept until you confirm'
                    '${err != null ? ' ($err)' : ''}',
                'confirmed' => 'Done — original deleted',
                'undone' => 'Undone — original back',
                'failed' => 'Failed — ${err ?? 'unknown error'} (original untouched)',
                'skipped' => 'Skipped — ${err ?? ''}',
                'cancelled' => 'Cancelled',
                _ => status,
              };
    final saved = neu != null && orig > 0 ? orig - neu : null;
    final year = j['year'] == null ? '' : ' (${j['year']})';
    return _card(
      focused: focused,
      poster: j['poster_path'] as String?,
      title: '${j['title']}$year',
      detail: detail,
      progress: status == 'running' ? ((j['progress'] ?? 0) as num).toDouble() : null,
      trailing: [
        const SizedBox(width: 22),
        Text(
            saved != null && (status == 'done' || status == 'confirmed')
                ? '−${fmtBytes(saved)}'
                : status == 'queued' || status == 'running'
                    ? '~${fmtBytes((j['savings_est'] ?? 0) as num)}'
                    : '',
            style: TextStyle(
                color: focused ? NasColors.bg : NasColors.ok,
                fontSize: 28,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// One movie's tracks: keep/drop and why, which track plays first afterwards,
/// X to strip it, Y to protect it. Pops `true` if anything changed.
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

  bool get _canStrip => _d?['status'] == 'strip' && _d?['job'] == null;

  Future<void> _strip() async {
    final d = _d;
    if (d == null || _busy || !_canStrip) return;
    setState(() => _busy = true);
    try {
      final res = await ApiService(widget.baseUrl)
          .queueStrip([(d['file_id'] as num).toInt()]);
      _changed = true;
      FlagService.say(((res['queued'] ?? const []) as List).isNotEmpty
          ? 'Queued — the original is kept until you confirm'
          : 'Not queued — it may already be clean');
      await _load();
    } catch (_) {
      FlagService.say('Couldn\'t queue it');
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).pop(_changed);
      case PadButton.x:
        _strip();
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
            LogicalKeyboardKey.keyX: PadButton.x,
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
                            if (_canStrip) (PadGlyph.x, 'Strip this movie'),
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
    final job = d['job'] as Map?;
    switch (d['status']) {
      case 'strip' when job != null:
        parts.add(switch (job['status']) {
          'running' => 'stripping now — ${(((job['progress'] ?? 0) as num) * 100).round()}%',
          'done' => 'stripped — original kept until you confirm',
          _ => 'queued to strip',
        });
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
