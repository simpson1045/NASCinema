/// Display refresh-rate matching (Windows renderer): set the desktop mode to
/// the film's cadence on play, restore the previous mode on stop. 3:2
/// pulldown at 60 Hz is what made 24p look harsh ("the whole film looks
/// smoother now" the night ELKO first ran at 23.976); once the theater runs a
/// 4K120 chain this becomes a no-op (23.976 × 5 = 119.88 — perfect 5:5).
///
/// Implementation = the RefreshSync reference recipe (ChangeDisplaySettings,
/// fps → Windows-mode map, restore-on-stop) moved inside the client, per the
/// 2026-08-23 decision. Must run in the interactive session — services see no
/// display. Open hardware question tracked in the settings copy: whether a
/// programmatic mode change drops Windows HDR on NVIDIA (verify on ELKO; if
/// so, re-assert via DisplayConfigSetDeviceInfo).
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _user32 = DynamicLibrary.open('user32.dll');

final _enumDisplaySettings = _user32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Pointer<Uint8>),
    int Function(Pointer<Utf16>, int, Pointer<Uint8>)>('EnumDisplaySettingsW');

final _changeDisplaySettingsEx = _user32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<Uint8>, IntPtr, Uint32, Pointer<Void>),
    int Function(Pointer<Utf16>, Pointer<Uint8>, int, int,
        Pointer<Void>)>('ChangeDisplaySettingsExW');

// DEVMODEW field offsets (the struct is 220 bytes; we only touch these).
const _devmodeSize = 220;
const _offSize = 68; // USHORT dmSize
const _offFields = 72; // DWORD dmFields
const _offBitsPerPel = 168; // DWORD
const _offPelsWidth = 172; // DWORD
const _offPelsHeight = 176; // DWORD
const _offFrequency = 184; // DWORD dmDisplayFrequency

const _enumCurrentSettings = 0xFFFFFFFF;
const _dmBitsPerPel = 0x40000;
const _dmPelsWidth = 0x80000;
const _dmPelsHeight = 0x100000;
const _dmDisplayFrequency = 0x400000;
const _dispChangeSuccessful = 0;

int _dw(Pointer<Uint8> p, int off) => (p + off).cast<Uint32>().value;
void _setDw(Pointer<Uint8> p, int off, int v) =>
    (p + off).cast<Uint32>().value = v;

/// A captured display mode (what to restore on stop).
class DisplayMode {
  const DisplayMode(this.width, this.height, this.bpp, this.hz);
  final int width;
  final int height;
  final int bpp;
  final int hz;

  @override
  String toString() => '${width}x$height@$hz';
}

/// Windows lists film rates as integer Hz: 23 = 23.976, 59 = 59.94. Candidate
/// order per container fps — first mode the display actually exposes wins.
List<int> _candidatesFor(double fps) {
  if ((fps - 23.976).abs() < 0.05) return const [23, 24, 120, 119];
  if ((fps - 24).abs() < 0.05) return const [24, 23, 120];
  if ((fps - 25).abs() < 0.05) return const [25, 50, 100];
  if ((fps - 29.97).abs() < 0.05) return const [29, 30, 59, 60];
  if ((fps - 30).abs() < 0.05) return const [30, 60, 120];
  if ((fps - 50).abs() < 0.05) return const [50, 100, 25];
  if ((fps - 59.94).abs() < 0.05) return const [59, 60, 119, 120];
  if ((fps - 60).abs() < 0.05) return const [60, 120, 59];
  return const [];
}

class RefreshRate {
  /// The primary display's current mode, or null off-Windows/on failure.
  static DisplayMode? current() {
    final dm = calloc<Uint8>(_devmodeSize);
    try {
      (dm + _offSize).cast<Uint16>().value = _devmodeSize;
      if (_enumDisplaySettings(nullptr, _enumCurrentSettings, dm) == 0) {
        return null;
      }
      return DisplayMode(_dw(dm, _offPelsWidth), _dw(dm, _offPelsHeight),
          _dw(dm, _offBitsPerPel), _dw(dm, _offFrequency));
    } finally {
      calloc.free(dm);
    }
  }

  /// True if the display exposes [hz] at the current resolution/depth.
  static bool _modeExists(DisplayMode cur, int hz) {
    final dm = calloc<Uint8>(_devmodeSize);
    try {
      var i = 0;
      while (true) {
        (dm + _offSize).cast<Uint16>().value = _devmodeSize;
        if (_enumDisplaySettings(nullptr, i++, dm) == 0) return false;
        if (_dw(dm, _offPelsWidth) == cur.width &&
            _dw(dm, _offPelsHeight) == cur.height &&
            _dw(dm, _offBitsPerPel) == cur.bpp &&
            _dw(dm, _offFrequency) == hz) {
          return true;
        }
      }
    } finally {
      calloc.free(dm);
    }
  }

  static bool _apply(DisplayMode mode) {
    final dm = calloc<Uint8>(_devmodeSize);
    try {
      (dm + _offSize).cast<Uint16>().value = _devmodeSize;
      _setDw(dm, _offFields,
          _dmPelsWidth | _dmPelsHeight | _dmBitsPerPel | _dmDisplayFrequency);
      _setDw(dm, _offPelsWidth, mode.width);
      _setDw(dm, _offPelsHeight, mode.height);
      _setDw(dm, _offBitsPerPel, mode.bpp);
      _setDw(dm, _offFrequency, mode.hz);
      // Flags 0 = dynamic change, NOT written to the registry — a crash or
      // power cut leaves the user's configured mode untouched.
      return _changeDisplaySettingsEx(nullptr, dm, 0, 0, nullptr) ==
          _dispChangeSuccessful;
    } finally {
      calloc.free(dm);
    }
  }

  /// Match the display to [fps]. Returns the mode to restore on stop (null =
  /// nothing changed: already matched — including an even multiple like
  /// 120 Hz for 24 fps — no candidate available, or the switch failed).
  static DisplayMode? matchFps(double fps, {void Function(String)? onDiag}) {
    final cur = current();
    if (cur == null || fps <= 0) return null;
    final candidates = _candidatesFor(fps);
    if (candidates.isEmpty) {
      onDiag?.call('refresh: no mode map for $fps fps');
      return null;
    }
    // Already clean? Integer-multiple refresh = even cadence, leave it be.
    // (23 Hz ≈ 23.976: treat 23/119 as the fractional rates they really are.)
    final effective = {23: 23.976, 29: 29.97, 59: 59.94, 119: 119.88}[cur.hz] ??
        cur.hz.toDouble();
    final ratio = effective / fps;
    if ((ratio - ratio.roundToDouble()).abs() < 0.001 && ratio >= 1) {
      onDiag?.call('refresh: ${cur.hz} Hz already matches $fps fps');
      return null;
    }
    for (final hz in candidates) {
      if (!_modeExists(cur, hz)) continue;
      final target = DisplayMode(cur.width, cur.height, cur.bpp, hz);
      if (_apply(target)) {
        onDiag?.call('refresh: $cur → $target for $fps fps');
        return cur;
      }
      onDiag?.call('refresh: switch to $target FAILED');
      return null;
    }
    onDiag?.call('refresh: no candidate of $candidates exists at '
        '${cur.width}x${cur.height}');
    return null;
  }

  /// Put back the mode captured by [matchFps].
  static void restore(DisplayMode mode, {void Function(String)? onDiag}) {
    onDiag?.call(_apply(mode)
        ? 'refresh: restored $mode'
        : 'refresh: restore to $mode FAILED');
  }
}
