import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/big_picture_prefs.dart';
import '../services/display_hdr.dart';
import '../services/hdr_prefs.dart';
import '../services/theater/theater_prefs.dart';
import '../services/theater/webos_control.dart';
import '../theme/app_theme.dart';

/// Client settings. The Home Theater section only appears on the Windows
/// renderer — it drives hardware wired to THAT machine (AVR input switching,
/// the C2 PC-label guard, display refresh matching). Everything is a pref:
/// no host, input name, or label lives in code (multi-user & config-driven).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SharedPreferences? _prefs;

  // Denon
  bool _denonEnabled = false;
  bool _denonPower = true;
  late final _denonHost = TextEditingController();
  late final _denonInput = TextEditingController();

  // LG TV
  bool _tvEnabled = false;
  bool _tvSwitch = false;
  bool _tvPaired = false;
  bool _pairing = false;
  String? _pairResult;
  late final _tvHost = TextEditingController();
  late final _tvInput = TextEditingController();
  late final _tvLabel = TextEditingController();

  // Display
  bool _refreshMatch = false;
  bool _bigPicture = true;
  HdrMode _hdrMode = HdrMode.auto;
  bool? _hdrDetected; // what Auto sees on this device's display

  // Renderer
  late final _mpvPath = TextEditingController();

  bool get _isRenderer => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
    displayHdrActive().then((on) {
      if (mounted) setState(() => _hdrDetected = on);
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _bigPicture = p.getBool(kBigPicturePref) ?? true;
      _hdrMode = HdrMode.values.asNameMap()[p.getString(kHdrTrailersPref)] ??
          HdrMode.auto;
      _denonEnabled = p.getBool(kDenonEnabledPref) ?? false;
      _denonPower = p.getBool(kDenonPowerPref) ?? true;
      _denonHost.text = p.getString(kDenonHostPref) ?? '';
      _denonInput.text = p.getString(kDenonInputPref) ?? '';
      _tvEnabled = p.getBool(kTvEnabledPref) ?? false;
      _tvSwitch = p.getBool(kTvSwitchInputPref) ?? false;
      _tvPaired = (p.getString(kTvKeyPref) ?? '').isNotEmpty;
      _tvHost.text = p.getString(kTvHostPref) ?? '';
      _tvInput.text = p.getString(kTvInputPref) ?? kDefaultTvInput;
      _tvLabel.text = p.getString(kTvLabelPref) ?? kDefaultTvLabel;
      _refreshMatch = p.getBool(kRefreshMatchPref) ?? false;
      _mpvPath.text = p.getString(kMpvPathPref) ?? kMpvDefaultPath;
    });
  }

  @override
  void dispose() {
    for (final c in [_denonHost, _denonInput, _tvHost, _tvInput, _tvLabel, _mpvPath]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pairTv() async {
    final host = _tvHost.text.trim();
    if (host.isEmpty || _pairing) return;
    await _prefs?.setString(kTvHostPref, host);
    setState(() {
      _pairing = true;
      _pairResult = 'Check the TV — accept the pairing prompt…';
    });
    final tv = await WebOsControl.connect(host);
    if (!mounted) return;
    if (tv != null && tv.clientKey != null) {
      await _prefs?.setString(kTvKeyPref, tv.clientKey!);
      tv.close();
      setState(() {
        _pairing = false;
        _tvPaired = true;
        _pairResult = 'Paired ✓';
      });
    } else {
      tv?.close();
      setState(() {
        _pairing = false;
        _pairResult = 'Pairing failed — is the TV on and on this network?';
      });
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: NasColors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      );

  Widget _toggle(String title, String subtitle, bool value,
          void Function(bool) onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: NasColors.muted, fontSize: 12.5)),
        activeThumbColor: NasColors.amber,
        value: value,
        onChanged: onChanged,
      );

  /// HDR trailers: Auto / Always / Never. Auto follows whether HDR is on for
  /// this device's display (shown underneath so it's never a mystery).
  Widget _hdrRow() {
    final detected = _hdrDetected;
    final autoNote = detected == null
        ? ''
        : detected
            ? ' Right now: HDR is on for this display.'
            : ' Right now: this display is SDR.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HDR trailers', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Play trailers in HDR when the trailer has it. Auto uses HDR when '
            'it\'s switched on for this display.$autoNote',
            style: const TextStyle(color: NasColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          SegmentedButton<HdrMode>(
            segments: const [
              ButtonSegment(value: HdrMode.auto, label: Text('Auto')),
              ButtonSegment(value: HdrMode.always, label: Text('Always')),
              ButtonSegment(value: HdrMode.never, label: Text('Never')),
            ],
            selected: {_hdrMode},
            showSelectedIcon: false,
            // Gold like the toggles (the theme's default here is violet).
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: NasColors.amber,
              selectedForegroundColor: NasColors.bg,
              foregroundColor: NasColors.text,
              side: const BorderSide(color: NasColors.amber),
            ),
            onSelectionChanged: (sel) {
              setState(() => _hdrMode = sel.first);
              HdrPrefs.setMode(sel.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
          String prefKey) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: NasColors.muted, fontSize: 13),
            hintText: hint,
            isDense: true,
          ),
          onChanged: (v) => _prefs?.setString(prefKey, v.trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: NasColors.amber)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isRenderer) ...[
            _section('RECEIVER (DENON AVR)', [
              _toggle(
                  'Switch the receiver on Play',
                  'Telnet: power on the main zone and select this PC\'s input '
                      'when a movie starts.',
                  _denonEnabled, (v) {
                setState(() => _denonEnabled = v);
                _prefs?.setBool(kDenonEnabledPref, v);
              }),
              if (_denonEnabled) ...[
                _field(_denonHost, 'Receiver address', '192.168.1.50',
                    kDenonHostPref),
                _field(_denonInput, 'Input source name', '8K', kDenonInputPref),
                _toggle('Power on first', 'Send main-zone power before the '
                    'input switch (skip if it\'s always on).', _denonPower, (v) {
                  setState(() => _denonPower = v);
                  _prefs?.setBool(kDenonPowerPref, v);
                }),
              ],
            ]),
            _section('TV (LG webOS)', [
              _toggle(
                  'Guard the TV\'s picture settings',
                  'LG TVs silently relabel a PC source as "PC", which disables '
                      'TruMotion/Real Cinema. On Play, put the label back.',
                  _tvEnabled, (v) {
                setState(() => _tvEnabled = v);
                _prefs?.setBool(kTvEnabledPref, v);
              }),
              if (_tvEnabled) ...[
                _field(_tvHost, 'TV address', '192.168.1.60', kTvHostPref),
                _field(_tvInput, 'Input to guard', kDefaultTvInput, kTvInputPref),
                _field(_tvLabel, 'Label to apply', kDefaultTvLabel, kTvLabelPref),
                _toggle('Also switch the TV to this input on Play',
                    'Uses the same webOS channel.', _tvSwitch, (v) {
                  setState(() => _tvSwitch = v);
                  _prefs?.setBool(kTvSwitchInputPref, v);
                }),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Row(children: [
                    ElevatedButton(
                      onPressed: _pairing ? null : _pairTv,
                      child: Text(_tvPaired ? 'Re-pair with TV' : 'Pair with TV'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pairResult ??
                            (_tvPaired
                                ? 'Paired ✓'
                                : 'Not paired yet — the TV will show an '
                                    'accept prompt.'),
                        style: TextStyle(
                            color: _tvPaired
                                ? NasColors.ok
                                : NasColors.muted,
                            fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
            _section('DISPLAY', [
              _toggle(
                  'Start in Big Picture',
                  'Open straight into the fullscreen TV layout (controller / '
                      'keyboard). Leave it any time from its Back menu.',
                  _bigPicture, (v) {
                setState(() => _bigPicture = v);
                _prefs?.setBool(kBigPicturePref, v);
              }),
              _hdrRow(),
              _toggle(
                  'Match display refresh rate to the movie',
                  'Switch the desktop to the film\'s cadence (e.g. 23.976 Hz) '
                      'on Play and restore it on Stop. No-op when the current '
                      'rate is already an even multiple (e.g. 120 Hz).',
                  _refreshMatch, (v) {
                setState(() => _refreshMatch = v);
                _prefs?.setBool(kRefreshMatchPref, v);
              }),
            ]),
            _section('RENDERER', [
              _field(_mpvPath, 'mpv path', kMpvDefaultPath, kMpvPathPref),
            ]),
          ] else
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Home-theater controls (receiver switching, TV guard, refresh '
                'matching) live on the Windows renderer — open Settings there.',
                style: TextStyle(color: NasColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
