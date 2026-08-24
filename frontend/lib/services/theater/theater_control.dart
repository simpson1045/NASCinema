/// The "press Play and the theater assembles itself" orchestrator.
///
/// On play (Windows renderer only): switch the Denon to this PC's input
/// (powering it on first), run the C2 PC-label guard (and optionally switch
/// the TV's input), and — once the container fps is known — match the
/// display refresh rate. On stop: restore the display mode.
///
/// Everything is config (multi-user, topology-agnostic): every hook is OFF
/// until enabled in Settings, hosts/inputs/labels are prefs, and every step
/// is best-effort — a dark AVR or unpaired TV logs a line, never blocks
/// playback.
library;

import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'denon_control.dart';
import 'refresh_rate.dart';
import 'theater_prefs.dart';
import 'webos_control.dart';

export 'theater_prefs.dart';

class TheaterControl {
  TheaterControl._();
  static final instance = TheaterControl._();

  DisplayMode? _restoreMode;
  bool _refreshWanted = false;

  /// Fire the AVR/TV hooks. Called as mpv launches; runs in the background.
  Future<void> onPlayStarted({void Function(String line)? diag}) async {
    if (!Platform.isWindows) return;
    final p = await SharedPreferences.getInstance();
    _refreshWanted = p.getBool(kRefreshMatchPref) ?? false;

    if (p.getBool(kDenonEnabledPref) ?? false) {
      final host = p.getString(kDenonHostPref) ?? '';
      final input = p.getString(kDenonInputPref) ?? '';
      if (host.isEmpty || input.isEmpty) {
        diag?.call('theater: denon enabled but host/input unset');
      } else {
        unawaited(DenonControl(host).powerAndSelect(input,
            power: p.getBool(kDenonPowerPref) ?? true, onDiag: diag));
      }
    }

    if (p.getBool(kTvEnabledPref) ?? false) {
      unawaited(_tvHooks(p, diag));
    }
  }

  Future<void> _tvHooks(
      SharedPreferences p, void Function(String line)? diag) async {
    final host = p.getString(kTvHostPref) ?? '';
    final key = p.getString(kTvKeyPref);
    if (host.isEmpty || key == null || key.isEmpty) {
      diag?.call('theater: TV enabled but not paired (Settings → Pair)');
      return;
    }
    final tv = await WebOsControl.connect(host, clientKey: key, onDiag: diag);
    if (tv == null) return;
    try {
      final inputId = p.getString(kTvInputPref) ?? kDefaultTvInput;
      final label = p.getString(kTvLabelPref) ?? kDefaultTvLabel;
      diag?.call('theater: PC-label guard → '
          '${await tv.ensureInputLabel(inputId, label)}');
      if (p.getBool(kTvSwitchInputPref) ?? false) {
        await tv.switchInput(inputId);
        diag?.call('theater: TV switched to $inputId');
      }
    } finally {
      tv.close();
    }
  }

  /// Match the display to the film's cadence. Call once mpv reports
  /// container-fps. Returns true if the mode actually changed (the caller
  /// should verify the exclusive audio device survived the HDMI renegotiate).
  bool onFpsKnown(double fps, {void Function(String line)? diag}) {
    if (!Platform.isWindows || !_refreshWanted) return false;
    // Only capture the FIRST pre-play mode: a second launch before a stop
    // (next movie) must not "restore" to the previous film's rate.
    final restore = RefreshRate.matchFps(fps, onDiag: diag);
    if (restore != null) _restoreMode ??= restore;
    return restore != null;
  }

  /// Put the desktop back. Called from player teardown.
  void onPlayStopped({void Function(String line)? diag}) {
    if (!Platform.isWindows) return;
    final mode = _restoreMode;
    _restoreMode = null;
    if (mode != null) RefreshRate.restore(mode, onDiag: diag);
  }
}
