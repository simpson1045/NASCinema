import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie_file.dart';
import '../../models/show.dart';
import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';
import '../player_screen.dart';
import 'bp_hero.dart' show bpLogoOver;
import 'bp_read_more.dart';
import 'bp_track_picker.dart';

/// A TV show page: backdrop, logo over "2022 · 2 seasons · TV-14", the
/// description, Play/Resume (the next episode), season tabs and the
/// season's episodes. LB/RB switch seasons from anywhere. When an episode
/// ends, the next one starts by itself.
class BpShowScreen extends StatefulWidget {
  const BpShowScreen({
    super.key,
    required this.baseUrl,
    required this.show,
    this.playEpisodeId,
  });

  final String baseUrl;
  // What the home row already knows; the full page is fetched.
  final Show show;
  // From Up Next on the home screen: open straight into this episode.
  final int? playEpisodeId;

  @override
  State<BpShowScreen> createState() => _BpShowScreenState();
}

enum _Row { overview, buttons, seasons, episodes }

class _BpShowScreenState extends State<BpShowScreen> {
  final _focus = FocusNode(debugLabel: 'bp-show');
  late final _api = ApiService(widget.baseUrl);
  ShowDetail? _d;
  bool _loading = true;

  _Row _row = _Row.buttons;
  int _button = 0; // 0 = Play/Resume, 1 = Start Over (when resuming)
  int _seasonIdx = 0;
  int _episodeIdx = 0;

  // One key per season tab, so the selected tab can be scrolled into view
  // (a 21-season show runs off the right edge — Whose Line).
  final _tabKeys = <int, GlobalKey>{};

  void _revealSeason() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[_seasonIdx]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.35, duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic);
      }
    });
  }

  static const _cardW = 420.0;
  static const _cardH = 236.0;
  static const _gap = 28.0;

  Show get _show => _d?.show ?? widget.show;
  List<ShowSeason> get _seasons => _d?.seasons ?? const [];
  int? get _seasonNo => _seasons.isEmpty ? null : _seasons[_seasonIdx].number;
  List<Episode> get _eps => (_d?.episodes ?? const [])
      .where((e) => e.season == _seasonNo)
      .toList();
  Episode? get _nextUp => _d?.nextUp;
  bool get _resuming => (_nextUp?.progress ?? 0) > 0;

  List<_Row> get _rows => [
        if ((_show.overview ?? '').isNotEmpty) _Row.overview,
        _Row.buttons,
        if (_seasons.length > 1) _Row.seasons,
        if (_eps.isNotEmpty) _Row.episodes,
      ];

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-show', widget.baseUrl, () {
      final e = _eps.isEmpty ? null : _eps[_episodeIdx.clamp(0, _eps.length - 1)];
      return {'show_id': _show.id, 'show_title': _show.title,
              'episode_id': e?.id, 'episode': e?.code};
    });
    _load(first: true);
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  /// Fetch (or re-fetch after playback). The first load lands on the
  /// next-up episode's season with it highlighted.
  Future<void> _load({bool first = false}) async {
    try {
      final d = await _api.getShow(widget.show.id);
      if (!mounted) return;
      setState(() {
        _d = d;
        _loading = false;
        if (first) _focusEpisode(d.nextUp ?? (d.episodes.isEmpty ? null : d.episodes.first));
      });
      _revealSeason();
      if (first && widget.playEpisodeId != null) {
        final e = d.episodes.where((e) => e.id == widget.playEpisodeId).firstOrNull;
        if (e != null) unawaited(_play(e));
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _focusEpisode(Episode? e) {
    if (e == null) return;
    final s = _seasons.indexWhere((s) => s.number == e.season);
    if (s >= 0) _seasonIdx = s;
    final i = _eps.indexWhere((x) => x.id == e.id);
    _episodeIdx = i < 0 ? 0 : i;
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  /// Play one episode; when it ends, the next one starts by itself.
  Future<void> _play(Episode e, {bool fromStart = false}) async {
    var ep = e;
    var restart = fromStart;
    while (mounted) {
      if (ep.files.isEmpty) return;
      final f = ep.files.first;
      final habitOn = await TrackPick.subtitlesHabit();
      final sub = habitOn ? TrackPick.preferredSubtitle(f) : null;
      if (!mounted) return;
      var current = ep; // advances as the player moves on in place
      final result = await Navigator.of(context).push<Object?>(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          fileId: f.id,
          baseUrl: widget.baseUrl,
          title: '${_show.title} · ${ep.code} · ${ep.displayTitle}',
          startAt: restart ? 0 : null,
          audioTrack: TrackPick.defaultAudio(f),
          subtitleTrack: sub ?? (TrackPick.autoSubtitle(f) == null ? 0 : null),
          versions: ep.files,
          popOnEnd: true,
          nextEpisode: () async {
            final n = _after(current);
            if (n == null || n.files.isEmpty) return null;
            current = n;
            return PlayerNext(
              fileId: n.files.first.id,
              title: '${_show.title} · ${n.code} · ${n.displayTitle}',
              label: '${n.code} · ${n.displayTitle}',
              versions: n.files,
            );
          },
        ),
      ));
      ep = current;
      if (!mounted) return;
      _focus.requestFocus();
      await _load();
      final next = result == 'ended' ? _after(ep) : null;
      if (next == null) {
        setState(() => _focusEpisode(_d?.nextUp ?? ep));
        _revealSeason();
        return;
      }
      FlagService.say('Up next: ${next.code} · ${next.displayTitle}');
      setState(() => _focusEpisode(next));
      ep = next;
      restart = true;
    }
  }

  /// The episode after [e] in watch order (specials last), if any.
  Episode? _after(Episode e) {
    final all = _d?.episodes ?? const <Episode>[];
    final i = all.indexWhere((x) => x.id == e.id);
    if (i < 0 || i + 1 >= all.length) return null;
    final next = all[i + 1];
    // Don't roll from the last real episode into the Specials.
    return (next.season == 0 && e.season != 0) ? null : next;
  }

  void _activate() {
    switch (_row) {
      case _Row.overview:
        showBpReadMore(context, title: _show.title, subtitle: _meta(), text: _show.overview ?? '');
      case _Row.buttons:
        final e = _nextUp ?? (_d?.episodes.firstOrNull);
        if (e != null) _play(e, fromStart: _button == 1 || _nextUp == null);
      case _Row.seasons:
        setState(() => _row = _Row.episodes);
      case _Row.episodes:
        if (_eps.isNotEmpty) _play(_eps[_episodeIdx.clamp(0, _eps.length - 1)]);
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _moveRow(int dir) {
    final rows = _rows;
    final i = rows.indexOf(_row);
    final j = (i + dir).clamp(0, rows.length - 1);
    if (j != i) setState(() => _row = rows[j]);
  }

  void _season(int dir) {
    final n = _seasons.length;
    if (n < 2) return;
    final s = (_seasonIdx + dir).clamp(0, n - 1);
    if (s == _seasonIdx) return;
    setState(() {
      _seasonIdx = s;
      _episodeIdx = 0;
    });
    _revealSeason();
  }

  void _sideways(int dir) {
    switch (_row) {
      case _Row.buttons:
        final n = _resuming ? 2 : 1;
        setState(() => _button = (_button + dir).clamp(0, n - 1));
      case _Row.seasons:
        _season(dir);
      case _Row.episodes:
        final n = _eps.length;
        setState(() => _episodeIdx = (_episodeIdx + dir).clamp(0, n - 1));
      case _Row.overview:
        break;
    }
  }

  bool _onPad(PadButton b) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    switch (b) {
      case PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.up:
        _moveRow(-1);
      case PadButton.down:
        _moveRow(1);
      case PadButton.left:
        _sideways(-1);
      case PadButton.right:
        _sideways(1);
      case PadButton.lb:
        _season(-1);
      case PadButton.rb:
        _season(1);
      case PadButton.a:
        _activate();
      default:
        return false;
    }
    return true;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final b = {
      LogicalKeyboardKey.arrowLeft: PadButton.left,
      LogicalKeyboardKey.arrowRight: PadButton.right,
      LogicalKeyboardKey.arrowUp: PadButton.up,
      LogicalKeyboardKey.arrowDown: PadButton.down,
      LogicalKeyboardKey.enter: PadButton.a,
      LogicalKeyboardKey.escape: PadButton.b,
      LogicalKeyboardKey.backspace: PadButton.b,
      LogicalKeyboardKey.pageUp: PadButton.lb,
      LogicalKeyboardKey.pageDown: PadButton.rb,
    }[e.logicalKey];
    if (b == null) return KeyEventResult.ignored;
    _onPad(b);
    return KeyEventResult.handled;
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  String _meta() {
    final s = _show;
    final seasons = _seasons.where((x) => x.number != 0).length;
    return [
      if (s.year != null) '${s.year}',
      if (seasons > 0) '$seasons season${seasons == 1 ? '' : 's'}',
      if ((s.certification ?? '').isNotEmpty) s.certification!,
      if (s.genres.isNotEmpty) s.genres.take(2).join(', '),
    ].join('  ·  ');
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
            child: SizedBox(width: 1920, height: 1080, child: ClipRect(child: _canvas())),
          ),
        ),
      ),
    );
  }

  Widget _canvas() {
    final backdrop = _show.backdropUrl(size: 'original');
    final eps = _eps;
    final focusedEp = eps.isEmpty ? null : eps[_episodeIdx.clamp(0, eps.length - 1)];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          Image.network(backdrop,
              fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x550A0E27), Color(0xCC0A0E27), Color(0xFF0A0E27)],
              stops: [0.0, 0.42, 0.66],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xCC0A0E27), Color(0x000A0E27)],
              stops: [0.0, 0.6],
            ),
          ),
        ),
        Positioned(left: 90, top: 70, width: 1100, child: _header()),
        Positioned(left: 90, top: 470, child: _buttons()),
        if (_seasons.length > 1) Positioned(left: 90, right: 0, top: 570, height: 60, child: _seasonTabs()),
        Positioned(
          left: 0,
          right: 0,
          top: 660,
          height: 340,
          child: _loading && eps.isEmpty
              ? const Center(child: CircularProgressIndicator(color: NasColors.amber))
              : _episodeRail(eps),
        ),
        if (focusedEp != null && _row == _Row.episodes)
          Positioned(
            left: 90,
            top: 975,
            width: 1500,
            child: Text(
              [focusedEp.overview ?? '', if (focusedEp.runtime != null) '${focusedEp.runtime} min']
                  .where((t) => t.isNotEmpty)
                  .join('   ·   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFDDE2F5), fontSize: 22),
            ),
          ),
        Positioned(
          right: 90,
          bottom: 30,
          child: PadHints([
            if (_seasons.length > 1) (PadGlyph.lb, 'Season'),
            if (_seasons.length > 1) (PadGlyph.rb, ''),
            (PadGlyph.a, _row == _Row.overview ? 'Read more' : 'Play'),
            (PadGlyph.b, 'Back'),
          ], size: 30, fontSize: 20),
        ),
      ],
    );
  }

  Widget _header() {
    final logoUrl = _d?.logo;
    final titleText = Align(
      alignment: Alignment.bottomCenter,
      child: Text(_show.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w800)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo centred over its line (house rule).
        bpLogoOver(
          logo: logoUrl == null
              ? titleText
              : Image.network(logoUrl,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  errorBuilder: (_, _, _) => titleText),
          below: Text(_meta(),
              style: const TextStyle(color: NasColors.text, fontSize: 30, fontWeight: FontWeight.w700)),
          logoHeight: 170,
          gap: 22,
          maxWidth: 760,
        ),
        if ((_show.overview ?? '').isNotEmpty) ...[
          const SizedBox(height: 22),
          bpOverviewFocus(
            width: 1000,
            focused: _row == _Row.overview,
            child: SizedBox(
              width: 1000,
              child: Text(_show.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFDDE2F5), fontSize: 28, height: 1.35)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buttons() {
    final e = _nextUp;
    final label = e == null
        ? 'Play from the start'
        : (_resuming ? 'Resume ${e.code}' : 'Play ${e.code}');
    return Row(children: [
      _btn(Icons.play_arrow_rounded, label, 0, primary: true, progress: e?.progress),
      if (_resuming) ...[
        const SizedBox(width: 24),
        _btn(Icons.replay_rounded, 'Start Over', 1),
      ],
    ]);
  }

  Widget _btn(IconData icon, String label, int i, {bool primary = false, double? progress}) {
    final focused = _row == _Row.buttons && _button == i;
    return GestureDetector(
      onTap: () {
        setState(() {
          _row = _Row.buttons;
          _button = i;
        });
        _activate();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: focused ? 1.06 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
          decoration: BoxDecoration(
            color: focused
                ? (primary ? NasColors.amber : Colors.white)
                : const Color(0x332A3070),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: focused ? Colors.white : const Color(0x55FFFFFF), width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 38, color: focused ? Colors.black : Colors.white),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: focused ? Colors.black : Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700)),
            ]),
            if (progress != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 220,
                height: 5,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0x44000000),
                  color: focused ? Colors.black : NasColors.amber,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _seasonTabs() {
    final focusedRow = _row == _Row.seasons;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Every tab built (a show has a couple dozen seasons at most), so the
      // selected one can always be scrolled into view.
      child: Row(children: [
        for (var i = 0; i < _seasons.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          _seasonTab(i, focusedRow),
        ],
        const SizedBox(width: 90),
      ]),
    );
  }

  Widget _seasonTab(int i, bool focusedRow) {
    final s = _seasons[i];
    final selected = i == _seasonIdx;
    final focused = focusedRow && selected;
    return GestureDetector(
      key: _tabKeys.putIfAbsent(i, GlobalKey.new),
      onTap: () {
        setState(() {
          _seasonIdx = i;
          _episodeIdx = 0;
        });
        _revealSeason();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: focused ? Colors.white : (selected ? const Color(0x55FFFFFF) : Colors.transparent),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? Colors.white : const Color(0x44FFFFFF), width: 2),
        ),
        child: Text(s.name,
            style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontSize: 24,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _episodeRail(List<Episode> eps) {
    final idx = _episodeIdx.clamp(0, eps.isEmpty ? 0 : eps.length - 1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: 90 - idx * (_cardW + _gap),
          top: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < eps.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                _episodeCard(eps[i], i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _episodeCard(Episode e, int i) {
    final focused = _row == _Row.episodes && i == _episodeIdx;
    final url = e.stillUrl();
    final p = e.progress;
    final MovieFile? f = e.files.isEmpty ? null : e.files.first;
    return GestureDetector(
      onTap: () {
        setState(() {
          _row = _Row.episodes;
          _episodeIdx = i;
        });
        _play(e);
      },
      child: SizedBox(
        width: _cardW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: focused ? 1.06 : 1,
              child: Container(
                width: _cardW,
                height: _cardH,
                decoration: BoxDecoration(
                  color: NasColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 4),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  if (url != null)
                    Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
                  else
                    Center(
                      child: Text(e.code,
                          style: const TextStyle(color: NasColors.muted, fontSize: 30, fontWeight: FontWeight.w700)),
                    ),
                  if (e.watched)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xCC000000),
                        child: Icon(Icons.check_rounded, color: NasColors.amber, size: 26),
                      ),
                    ),
                  if (p != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 8,
                      child: ColoredBox(
                        color: const Color(0xB0000000),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: p,
                          child: const ColoredBox(color: NasColors.amber),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [e.code, if (f?.quality != null) f!.quality!].join('   ·   '),
              style: TextStyle(
                  color: focused ? NasColors.amber : NasColors.muted, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(e.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: focused ? Colors.white : NasColors.text, fontSize: 26, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
