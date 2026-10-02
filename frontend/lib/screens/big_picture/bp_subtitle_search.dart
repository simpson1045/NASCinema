import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/flag_service.dart';
import '../../services/gamepad/pad_dispatch.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pad_hints.dart';

/// Search OpenSubtitles for one version (file) and download a pick. The
/// server matches by title and by a hash of this exact file (hash matches are
/// in sync). Pops with the downloaded subtitle ({id, lang, label, url}).
class BpSubtitleSearch extends StatefulWidget {
  const BpSubtitleSearch({
    super.key,
    required this.baseUrl,
    required this.fileId,
    required this.title,
    this.lang = 'en',
  });

  final String baseUrl;
  final int fileId;
  final String title;
  final String lang;

  @override
  State<BpSubtitleSearch> createState() => _BpSubtitleSearchState();
}

class _BpSubtitleSearchState extends State<BpSubtitleSearch> {
  final _focus = FocusNode(debugLabel: 'bp-subtitle-search');
  List<Map<String, dynamic>> _results = const [];
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  int _cursor = 0;
  static const _visible = 7;

  @override
  void initState() {
    super.initState();
    PadDispatch.add(_onPad);
    FlagService.register(this, 'bp-subtitle-search', widget.baseUrl,
        () => {'file_id': widget.fileId, 'results': _results.length});
    _search();
  }

  Future<void> _search() async {
    try {
      final r = await ApiService(widget.baseUrl)
          .searchSubtitles(widget.fileId, widget.lang);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.contains('503')
            ? 'Online subtitles aren\'t set up on this server (no OpenSubtitles key).'
            : 'Couldn\'t reach OpenSubtitles. Try again in a bit.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download() async {
    if (_results.isEmpty || _downloading) return;
    final pick = _results[_cursor];
    setState(() => _downloading = true);
    try {
      final entry = await ApiService(widget.baseUrl).downloadSubtitle(
          widget.fileId,
          (pick['os_file_id'] as num).toInt(),
          (pick['language'] ?? widget.lang).toString(),
          release: pick['release']?.toString());
      if (!mounted) return;
      FlagService.say('Subtitle downloaded');
      Navigator.of(context).pop(entry);
    } catch (_) {
      if (mounted) setState(() => _downloading = false);
      FlagService.say('Download failed — try another');
    }
  }

  @override
  void dispose() {
    PadDispatch.remove(_onPad);
    FlagService.unregister(this);
    _focus.dispose();
    super.dispose();
  }

  bool _onPad(PadButton b) {
    switch (b) {
      case PadButton.b:
        Navigator.of(context).maybePop();
      case PadButton.a:
        _download();
      case PadButton.up:
        if (_cursor > 0) setState(() => _cursor--);
      case PadButton.down:
        if (_cursor < _results.length - 1) setState(() => _cursor++);
      default:
        break;
    }
    return true;
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
          final b = {
            LogicalKeyboardKey.arrowUp: PadButton.up,
            LogicalKeyboardKey.arrowDown: PadButton.down,
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
                padding: const EdgeInsets.fromLTRB(90, 80, 90, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ONLINE SUBTITLES',
                        style: TextStyle(
                            color: NasColors.amber,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                    const SizedBox(height: 10),
                    Text(widget.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 46,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 36),
                    Expanded(child: _body()),
                    PadHints([
                      (PadGlyph.dpadVertical, 'Move'),
                      (PadGlyph.a, _downloading ? 'Downloading…' : 'Download'),
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

  Widget _body() {
    if (_loading) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Row(children: [
          SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(color: NasColors.amber)),
          SizedBox(width: 20),
          Text('Searching OpenSubtitles…',
              style: TextStyle(color: NasColors.muted, fontSize: 28)),
        ]),
      );
    }
    if (_error != null || _results.isEmpty) {
      return Text(_error ?? 'No subtitles found for this version.',
          style: const TextStyle(color: NasColors.muted, fontSize: 28));
    }
    final first = (_cursor - _visible ~/ 2)
        .clamp(0, (_results.length - _visible).clamp(0, _results.length));
    final shown = _results.skip(first).take(_visible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          _row(shown[i], focused: first + i == _cursor),
        if (first + _visible < _results.length)
          const Text('▼', style: TextStyle(color: NasColors.muted, fontSize: 20)),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r, {required bool focused}) {
    final fg = focused ? NasColors.bg : Colors.white;
    final release = (r['release'] ?? '').toString();
    // The server ranks results by fit to THIS file and says why (tags);
    // older servers only send the flags.
    final serverTags = (r['tags'] as List?)?.map((t) => '$t'.toUpperCase()).toList();
    final tags = [
      if (r['best'] == true) 'BEST MATCH',
      ...?serverTags,
      if (serverTags == null && r['hearing_impaired'] == true) 'SDH',
      if (serverTags == null && r['from_trusted'] == true) 'TRUSTED',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(release.isEmpty ? 'Untitled release' : release,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          for (final t in tags)
            Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: t == 'BEST MATCH'
                        ? NasColors.amber
                        : (focused ? NasColors.bg : NasColors.muted)),
              ),
              child: Text(t,
                  style: TextStyle(
                      color: t == 'BEST MATCH'
                          ? NasColors.amber
                          : (focused ? NasColors.bg : NasColors.muted),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 18),
          Text('${r['downloads'] ?? 0} downloads',
              style: TextStyle(
                  color: focused ? NasColors.bg : NasColors.muted, fontSize: 20)),
        ],
      ),
    );
  }
}
