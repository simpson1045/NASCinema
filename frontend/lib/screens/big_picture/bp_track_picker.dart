import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/movie_file.dart';
import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';
import 'bp_hero.dart' show bpLogo, bpLogoOver;
import 'bp_subtitle_search.dart';

/// What Play will use: a version (file) and its audio/subtitle tracks, as mpv
/// ids. [audio] null = the file's default; [subtitle] null = automatic (mpv's
/// default/forced choice), 0 = off.
class TrackPick {
  const TrackPick(
      {required this.fileId, this.audio, this.subtitle, this.external});

  final int fileId;
  final int? audio;
  final int? subtitle;
  // A downloaded (OpenSubtitles) subtitle's id for this file — loaded by the
  // player at start; embedded subtitles are then off (subtitle 0).
  final String? external;

  TrackPick copyWith({
    int? fileId,
    int? audio,
    int? subtitle,
    String? external,
    bool clearAudio = false,
    bool clearSubtitle = false,
    bool clearExternal = false,
  }) =>
      TrackPick(
        fileId: fileId ?? this.fileId,
        audio: clearAudio ? null : (audio ?? this.audio),
        subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
        external: clearExternal ? null : (external ?? this.external),
      );

  static String _key(int movieId) => 'bp_pick_$movieId';

  /// The remembered pick for a movie, if it still matches its versions —
  /// else the default: best version, its default English (or first) audio.
  static Future<TrackPick?> load(int movieId, List<MovieFile> files) async {
    if (files.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(movieId));
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final f = files.where((f) => f.id == j['file']).firstOrNull;
        if (f != null) {
          int? keep(Object? id, List<MediaTrack> ts, {bool allowOff = false}) {
            final n = (id as num?)?.toInt();
            if (n == null) return null;
            if (allowOff && n == 0) return 0;
            return ts.any((t) => t.id == n) ? n : null;
          }

          final sub = keep(j['subtitle'], f.subtitleTracks, allowOff: true);
          return TrackPick(
            fileId: f.id,
            audio: keep(j['audio'], f.audioTracks),
            // "Automatic" only exists when the file has a forced/default
            // track; otherwise nothing would show, so say Off.
            subtitle: sub ?? (autoSubtitle(f) == null ? 0 : null),
            external: j['external'] as String?,
          );
        }
      }
    } catch (_) {}
    // Never set up: follow the habit — subtitles on last time → the plain
    // English track; otherwise the file's own forced/default, else off.
    final f = files.first;
    final habitOn = await subtitlesHabit();
    final preferred = habitOn ? preferredSubtitle(f) : null;
    return TrackPick(
        fileId: f.id,
        audio: defaultAudio(f),
        subtitle: preferred ?? (autoSubtitle(f) == null ? 0 : null));
  }

  static const _habitKey = 'bp_subs_habit_on';

  /// Whether subtitles were on the last time a movie was watched.
  static Future<bool> subtitlesHabit() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_habitKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSubtitlesHabit(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_habitKey, on);
    } catch (_) {}
  }

  /// The English track to turn on by default: plain dialogue text ("full",
  /// "Stripped SRT") before SDH, text before picture-based (PGS/VobSub),
  /// never a forced-only track. Null if there's no English subtitle.
  static int? preferredSubtitle(MovieFile f) {
    bool en(MediaTrack t) => (t.language ?? '').toLowerCase().startsWith('en');
    bool sdh(MediaTrack t) =>
        RegExp(r'sdh|hearing|\bcc\b', caseSensitive: false).hasMatch('${t.title} ${t.desc}');
    bool picture(MediaTrack t) =>
        RegExp(r'pgs|vobsub|dvd_sub|hdmv', caseSensitive: false).hasMatch('${t.title} ${t.desc}');
    final ts = f.subtitleTracks.where((t) => en(t) && !t.forced).toList();
    if (ts.isEmpty) return null;
    int rank(MediaTrack t) => (sdh(t) ? 1 : 0) + (picture(t) ? 2 : 0);
    ts.sort((a, b) => rank(a).compareTo(rank(b)));
    return ts.first.id;
  }

  /// The subtitle mpv shows on its own (no --sid): a forced track (foreign-
  /// language scenes), else one the file flags default. Null = none, so
  /// "Automatic" would just mean Off.
  static MediaTrack? autoSubtitle(MovieFile f) =>
      f.subtitleTracks.where((t) => t.forced).firstOrNull ??
      (defaultFlagMeans(f.subtitleTracks)
          ? f.subtitleTracks.where((t) => t.isDefault).firstOrNull
          : null);

  /// Some releases flag EVERY track "default" — then the flag says nothing
  /// (The Emperor's New Groove: ~20 dubs, Català first). More than one = ignore.
  static bool defaultFlagMeans(List<MediaTrack> ts) =>
      ts.where((t) => t.isDefault).length <= 1;

  Future<void> save(int movieId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(movieId),
          jsonEncode({
            'file': fileId,
            'audio': audio,
            'subtitle': subtitle,
            'external': external,
          }));
    } catch (_) {}
  }

  /// The file's default audio: flagged default (when the flag means
  /// something), else first English, else first.
  static int? defaultAudio(MovieFile f, {String? preferLang}) {
    final ts = f.audioTracks.where((t) => !t.commentary).toList();
    if (ts.isEmpty) return null;
    final flagged = defaultFlagMeans(f.audioTracks);
    if (preferLang != null) {
      final same = ts.where((t) => t.language == preferLang);
      if (same.isNotEmpty) {
        return ((flagged ? same.where((t) => t.isDefault).firstOrNull : null) ??
                same.first)
            .id;
      }
    }
    return ((flagged ? ts.where((t) => t.isDefault).firstOrNull : null) ??
            ts.where((t) => (t.language ?? '').startsWith('en')).firstOrNull ??
            ts.first)
        .id;
  }

  /// "4K77 · 1.0 DTS-HD-MA (1977 35mm mono mix) · Subtitles off"
  String summary(List<MovieFile> files) {
    final f = files.where((f) => f.id == fileId).firstOrNull;
    if (f == null) return '';
    final a = f.audioTracks.where((t) => t.id == audio).firstOrNull;
    final s = f.subtitleTracks.where((t) => t.id == subtitle).firstOrNull;
    return [
      if (files.length > 1) f.label ?? f.quality ?? 'Version',
      a?.title ?? (f.audioTracks.isEmpty ? 'Audio' : 'Default audio'),
      external != null
          ? 'Subtitles: downloaded (${external!.split('-').first.toUpperCase()})'
          : subtitle == 0
              ? 'Subtitles off'
              : s != null
                  ? 'Subtitles: ${s.title}'
                  : 'Subtitles: automatic',
    ].join('  ·  ');
  }
}

/// Full-screen Version | Audio | Subtitles picker for the controller.
/// ←/→ columns · ↑/↓ items · A pick (and step right) · B done.
/// Pops with the final [TrackPick].
class BpTrackPicker extends StatefulWidget {
  const BpTrackPicker({
    super.key,
    required this.title,
    required this.files,
    required this.initial,
    required this.baseUrl,
    this.logo,
    this.logoSubtitle,
  });

  final String title;
  final String? logo; // clearlogo shown instead of the title text
  final String? logoSubtitle;
  final List<MovieFile> files;
  final TrackPick initial;
  final String baseUrl;

  @override
  State<BpTrackPicker> createState() => _BpTrackPickerState();
}

class _Item {
  const _Item(this.value, this.title,
      {this.desc = '', this.tags = const [], this.dim = false});
  final int? value;
  final String title;
  final String desc;
  final List<String> tags;
  final bool dim; // commentary / other-language — still pickable, less loud
}

class _BpTrackPickerState extends State<BpTrackPicker> {
  final _focus = FocusNode(debugLabel: 'bp-track-picker');
  late TrackPick _pick = widget.initial;
  late int _col = widget.files.length > 1 ? 0 : 1;
  final _cursor = [0, 0, 0];
  // Downloaded subtitles for the chosen version ({id, lang, label, url}).
  List<Map<String, dynamic>> _externals = const [];
  static const _searchOnline = -9999; // the "Search online…" row's value

  static const _visible = 8; // rows shown per column; the list scrolls

  MovieFile get _file =>
      widget.files.where((f) => f.id == _pick.fileId).firstOrNull ??
      widget.files.first;

  List<_Item> _items(int col) {
    switch (col) {
      case 0:
        return [
          for (final f in widget.files)
            _Item(f.id, f.label ?? f.filename,
                desc: [
                  if (f.label != null && f.label != f.quality) f.quality ?? '',
                  if (f.durationLabel != null) f.durationLabel!,
                ].where((s) => s.isNotEmpty).join('  ·  ')),
        ];
      case 1:
        return [
          for (final t in _file.audioTracks)
            _Item(t.id, t.title,
                desc: t.title == t.desc ? '' : t.desc,
                tags: [
                  if (t.lossless) 'LOSSLESS',
                  if (t.commentary) 'COMMENTARY',
                  if (t.isDefault && TrackPick.defaultFlagMeans(_file.audioTracks))
                    'DEFAULT',
                ],
                dim: t.commentary ||
                    !((t.language ?? 'en').startsWith('en') ||
                        t.language == null)),
        ];
      default:
        final auto = TrackPick.autoSubtitle(_file);
        return [
          if (auto != null)
            _Item(null, 'Automatic',
                desc: auto.forced
                    ? 'Shows "${auto.title}" for foreign-language scenes'
                    : 'Shows "${auto.title}" (the file\'s default)'),
          const _Item(0, 'Off'),
          for (final t in _file.subtitleTracks)
            _Item(t.id, t.title,
                desc: t.title == t.desc ? '' : t.desc,
                tags: [
                  if (t.forced) 'FORCED',
                  if (t.isDefault && TrackPick.defaultFlagMeans(_file.subtitleTracks))
                    'DEFAULT',
                ],
                dim: !((t.language ?? 'en').startsWith('en'))),
          // Downloaded ones: negative values index _externals.
          for (var i = 0; i < _externals.length; i++)
            _Item(-(i + 1),
                'Downloaded · ${(_externals[i]['label'] ?? '').toString()}',
                desc: 'From OpenSubtitles',
                tags: const ['ONLINE']),
          const _Item(_searchOnline, 'Search online…',
              desc: 'Find subtitles on OpenSubtitles for this version'),
        ];
    }
  }

  int? _selected(int col) {
    if (col == 0) return _pick.fileId;
    if (col == 1) return _pick.audio;
    final ext = _pick.external;
    if (ext != null) {
      final i = _externals.indexWhere((e) => e['id'] == ext);
      if (i >= 0) return -(i + 1);
    }
    return _pick.subtitle;
  }

  Future<void> _loadExternals() async {
    try {
      final r = await ApiService(widget.baseUrl).getSubtitles(_pick.fileId);
      if (!mounted) return;
      setState(() {
        _externals = r.subtitles;
        final i = _items(2).indexWhere((it) => it.value == _selected(2));
        if (i >= 0) _cursor[2] = i;
      });
    } catch (_) {}
  }

  Future<void> _searchOnlineSubs() async {
    final entry = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => BpSubtitleSearch(
          baseUrl: widget.baseUrl,
          fileId: _pick.fileId,
          title: widget.title,
        ),
      ),
    );
    if (!mounted || entry == null) return;
    setState(() {
      _externals = [..._externals.where((e) => e['id'] != entry['id']), entry];
      _pick = TrackPick(
          fileId: _pick.fileId,
          audio: _pick.audio,
          subtitle: 0,
          external: entry['id'] as String?);
    });
    _done();
  }

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-track-picker', widget.baseUrl);
    // Start each column's cursor on its current choice.
    for (var c = 0; c < 3; c++) {
      final i = _items(c).indexWhere((it) => it.value == _selected(c));
      _cursor[c] = i < 0 ? 0 : i;
    }
    _loadExternals();
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_pick);

  void _choose() {
    final items = _items(_col);
    if (items.isEmpty) return;
    final v = items[_cursor[_col]].value;
    setState(() {
      if (_col == 0) {
        if (v != _pick.fileId) {
          // New version: keep the audio language if it has one.
          final lang = _file.audioTracks
              .where((t) => t.id == _pick.audio)
              .firstOrNull
              ?.language;
          final f = widget.files.firstWhere((f) => f.id == v);
          _pick = TrackPick(
              fileId: f.id,
              audio: TrackPick.defaultAudio(f, preferLang: lang),
              subtitle: _pick.subtitle == 0 || TrackPick.autoSubtitle(f) == null
                  ? 0
                  : null);
          // Downloads belong to a file: fetch the new version's.
          _externals = const [];
          _loadExternals();
          final ai = _items(1).indexWhere((it) => it.value == _pick.audio);
          _cursor[1] = ai < 0 ? 0 : ai;
          final si = _items(2).indexWhere((it) => it.value == _pick.subtitle);
          _cursor[2] = si < 0 ? 0 : si;
        }
        _col = 1;
      } else if (_col == 1) {
        _pick = _pick.copyWith(audio: v);
        _col = 2;
      } else if (v == _searchOnline) {
        _searchOnlineSubs();
      } else if (v != null && v < 0) {
        final e = _externals[-v - 1];
        _pick = TrackPick(
            fileId: _pick.fileId,
            audio: _pick.audio,
            subtitle: 0,
            external: e['id'] as String?);
        _done();
      } else {
        _pick = TrackPick(
            fileId: _pick.fileId, audio: _pick.audio, subtitle: v);
        _done();
      }
    });
  }

  bool _onPad(PadButton b) {
    switch (b) {
      case PadButton.b:
        _done();
      case PadButton.a:
        _choose();
      case PadButton.left:
        setState(() => _col = (_col - 1).clamp(widget.files.length > 1 ? 0 : 1, 2));
      case PadButton.right:
        setState(() => _col = (_col + 1).clamp(0, 2));
      case PadButton.up:
      case PadButton.down:
        final n = _items(_col).length;
        if (n > 0) {
          setState(() => _cursor[_col] =
              (_cursor[_col] + (b == PadButton.down ? 1 : -1)).clamp(0, n - 1));
        }
      default:
        break;
    }
    return true; // nothing falls through to the page underneath
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xF20A0E27),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey.keyLabel;
          final map = {
            'Arrow Up': PadButton.up, 'Arrow Down': PadButton.down,
            'Arrow Left': PadButton.left, 'Arrow Right': PadButton.right,
            'Enter': PadButton.a, 'Escape': PadButton.b,
            'Backspace': PadButton.b,
          };
          final b = map[k];
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
                padding: const EdgeInsets.fromLTRB(90, 80, 90, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo centred over the summary line (house rule).
                    bpLogoOver(
                      logo: _header(),
                      logoHeight: 130,
                      gap: 14,
                      maxWidth: 1400,
                      below: Text(_pickSummary(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NasColors.amber,
                              fontSize: 26,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 40),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.files.length > 1) ...[
                            Expanded(flex: 4, child: _column(0, 'VERSION')),
                            const SizedBox(width: 36),
                          ],
                          Expanded(flex: 6, child: _column(1, 'AUDIO')),
                          const SizedBox(width: 36),
                          Expanded(flex: 5, child: _column(2, 'SUBTITLES')),
                        ],
                      ),
                    ),
                    const PadHints([
                      (PadGlyph.a, 'Choose'),
                      (PadGlyph.dpadHorizontal, 'Column'),
                      (PadGlyph.dpadVertical, 'Move'),
                      (PadGlyph.b, 'Done'),
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

  String _pickSummary() => _pick.summary(widget.files);

  Widget _header() {
    final text = Align(
      alignment: Alignment.bottomCenter,
      child: Text(widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800)),
    );
    final logo = widget.logo;
    if (logo == null || logo.isEmpty) return text;
    return bpLogo(logo, widget.logoSubtitle, text,
        subtitleSize: 30, centered: true);
  }

  Widget _column(int col, String heading) {
    final items = _items(col);
    final active = col == _col;
    final cur = _cursor[col];
    final first = (cur - _visible ~/ 2).clamp(0,
        (items.length - _visible).clamp(0, items.length));
    final shown = items.skip(first).take(_visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading,
            style: TextStyle(
                color: active ? NasColors.amber : NasColors.muted,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Text('None',
              style: TextStyle(color: NasColors.muted, fontSize: 26)),
        if (first > 0)
          const Text('▲',
              style: TextStyle(color: NasColors.muted, fontSize: 20)),
        for (var i = 0; i < shown.length; i++)
          _row(shown[i],
              focused: active && first + i == cur,
              chosen: shown[i].value == _selected(col)),
        if (first + _visible < items.length)
          const Text('▼',
              style: TextStyle(color: NasColors.muted, fontSize: 20)),
      ],
    );
  }

  Widget _row(_Item it, {required bool focused, required bool chosen}) {
    final fg = focused ? NasColors.bg : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(
                color: chosen ? NasColors.amber : Colors.transparent, width: 6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: it.dim && !focused
                            ? Colors.white.withValues(alpha: 0.6)
                            : fg,
                        fontSize: 26,
                        fontWeight: FontWeight.w700)),
                if (it.desc.isNotEmpty)
                  Text(it.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: focused ? NasColors.bg : NasColors.muted,
                          fontSize: 20)),
              ],
            ),
          ),
          for (final t in it.tags)
            Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t == 'LOSSLESS' ? NasColors.amber : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: t == 'LOSSLESS'
                        ? NasColors.amber
                        : (focused ? NasColors.bg : NasColors.muted)),
              ),
              child: Text(t,
                  style: TextStyle(
                      color: t == 'LOSSLESS'
                          ? NasColors.bg
                          : (focused ? NasColors.bg : NasColors.muted),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          if (chosen)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(Icons.check_rounded,
                  color: focused ? NasColors.bg : NasColors.amber, size: 30),
            ),
        ],
      ),
    );
  }
}
