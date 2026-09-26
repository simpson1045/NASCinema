import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/movie_file.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';
import 'bp_hero.dart' show bpLogo;

/// What Play will use: a version (file) and its audio/subtitle tracks, as mpv
/// ids. [audio] null = the file's default; [subtitle] null = automatic (mpv's
/// default/forced choice), 0 = off.
class TrackPick {
  const TrackPick({required this.fileId, this.audio, this.subtitle});

  final int fileId;
  final int? audio;
  final int? subtitle;

  TrackPick copyWith({int? fileId, int? audio, int? subtitle, bool clearAudio = false,
          bool clearSubtitle = false}) =>
      TrackPick(
        fileId: fileId ?? this.fileId,
        audio: clearAudio ? null : (audio ?? this.audio),
        subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
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
          );
        }
      }
    } catch (_) {}
    return TrackPick(
        fileId: files.first.id,
        audio: defaultAudio(files.first),
        subtitle: autoSubtitle(files.first) == null ? 0 : null);
  }

  /// The subtitle mpv shows on its own (no --sid): a forced track (foreign-
  /// language scenes), else one the file flags default. Null = none, so
  /// "Automatic" would just mean Off.
  static MediaTrack? autoSubtitle(MovieFile f) =>
      f.subtitleTracks.where((t) => t.forced).firstOrNull ??
      f.subtitleTracks.where((t) => t.isDefault).firstOrNull;

  Future<void> save(int movieId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(movieId),
          jsonEncode({'file': fileId, 'audio': audio, 'subtitle': subtitle}));
    } catch (_) {}
  }

  /// The file's default audio: flagged default, else first English, else first.
  static int? defaultAudio(MovieFile f, {String? preferLang}) {
    final ts = f.audioTracks.where((t) => !t.commentary).toList();
    if (ts.isEmpty) return null;
    if (preferLang != null) {
      final same = ts.where((t) => t.language == preferLang);
      if (same.isNotEmpty) {
        return (same.where((t) => t.isDefault).firstOrNull ?? same.first).id;
      }
    }
    return (ts.where((t) => t.isDefault).firstOrNull ??
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
      subtitle == 0
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
                  if (t.isDefault) 'DEFAULT',
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
                tags: [if (t.forced) 'FORCED', if (t.isDefault) 'DEFAULT'],
                dim: !((t.language ?? 'en').startsWith('en'))),
        ];
    }
  }

  int? _selected(int col) => switch (col) {
        0 => _pick.fileId,
        1 => _pick.audio,
        _ => _pick.subtitle,
      };

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
          final ai = _items(1).indexWhere((it) => it.value == _pick.audio);
          _cursor[1] = ai < 0 ? 0 : ai;
          final si = _items(2).indexWhere((it) => it.value == _pick.subtitle);
          _cursor[2] = si < 0 ? 0 : si;
        }
        _col = 1;
      } else if (_col == 1) {
        _pick = _pick.copyWith(audio: v);
        _col = 2;
      } else {
        _pick = v == null
            ? _pick.copyWith(clearSubtitle: true)
            : _pick.copyWith(subtitle: v);
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
                    SizedBox(width: 560, height: 130, child: _header()),
                    const SizedBox(height: 14),
                    Text(_pickSummary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: NasColors.amber,
                            fontSize: 26,
                            fontWeight: FontWeight.w700)),
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
      alignment: Alignment.bottomLeft,
      child: Text(widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800)),
    );
    final logo = widget.logo;
    if (logo == null || logo.isEmpty) return text;
    return bpLogo(logo, widget.logoSubtitle, text, subtitleSize: 30);
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
