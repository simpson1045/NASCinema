/// Windows HDR ("advanced color") on/off per active display — for matching
/// the signal to the movie: an SDR film in Windows HDR goes out as PQ/BT.2020
/// with mpv mapping it inside, and the TV tone-maps a picture that was never
/// HDR (Van Halen - Live Without a Net, 2026-10-09). Same calls as ELKO's
/// elko-display.ps1 (DisplayConfigGet/SetDeviceInfo types 9/10). Must run in
/// the interactive session. Every failure is a logged no-op.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _user32 = DynamicLibrary.open('user32.dll');

final _getBufferSizes = _user32.lookupFunction<
    Int32 Function(Uint32, Pointer<Uint32>, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>, Pointer<Uint32>)>(
  'GetDisplayConfigBufferSizes',
);

final _queryDisplayConfig = _user32.lookupFunction<
    Int32 Function(Uint32, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>,
        Pointer<Uint8>, Pointer<Void>),
    int Function(int, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>,
        Pointer<Uint8>, Pointer<Void>)>('QueryDisplayConfig');

final _getDeviceInfo = _user32.lookupFunction<Int32 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('DisplayConfigGetDeviceInfo');

final _setDeviceInfo = _user32.lookupFunction<Int32 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('DisplayConfigSetDeviceInfo');

const _qdcOnlyActivePaths = 2;
const _pathSize = 72; // DISPLAYCONFIG_PATH_INFO
const _modeSize = 64; // DISPLAYCONFIG_MODE_INFO
const _offTargetAdapter = 20; // targetInfo.adapterId (LUID)
const _offTargetId = 28; // targetInfo.id
const _typeGetAdvancedColor = 9;
const _typeSetAdvancedColor = 10;

/// One active display's target, as DisplayConfig addresses it.
class HdrTarget {
  const HdrTarget(this.adapterLow, this.adapterHigh, this.id);
  final int adapterLow;
  final int adapterHigh;
  final int id;
}

class HdrMode {
  /// Active display targets that support HDR, with whether it's on now.
  static List<({HdrTarget target, bool on})> displays(
      {void Function(String line)? onDiag}) {
    final out = <({HdrTarget target, bool on})>[];
    final np = calloc<Uint32>();
    final nm = calloc<Uint32>();
    try {
      if (_getBufferSizes(_qdcOnlyActivePaths, np, nm) != 0) return out;
      final paths = calloc<Uint8>(np.value * _pathSize);
      final modes = calloc<Uint8>(nm.value * _modeSize);
      try {
        if (_queryDisplayConfig(
                _qdcOnlyActivePaths, np, paths, nm, modes, nullptr) !=
            0) {
          return out;
        }
        for (var i = 0; i < np.value; i++) {
          final p = paths + i * _pathSize;
          final t = HdrTarget(
            (p + _offTargetAdapter).cast<Uint32>().value,
            (p + _offTargetAdapter + 4).cast<Int32>().value,
            (p + _offTargetId).cast<Uint32>().value,
          );
          final v = _advancedColor(t);
          if (v == null || v & 1 == 0) continue; // not HDR-capable
          out.add((target: t, on: v & 2 != 0));
        }
      } finally {
        calloc.free(paths);
        calloc.free(modes);
      }
    } catch (e) {
      onDiag?.call('hdr: query failed: $e');
    } finally {
      calloc.free(np);
      calloc.free(nm);
    }
    return out;
  }

  /// DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO.value (bit0 supported, bit1 on).
  static int? _advancedColor(HdrTarget t) {
    final b = calloc<Uint8>(32);
    try {
      _header(b, _typeGetAdvancedColor, 32, t);
      return _getDeviceInfo(b) == 0 ? (b + 20).cast<Uint32>().value : null;
    } finally {
      calloc.free(b);
    }
  }

  /// Switch HDR on/off for [t]; true on success.
  static bool set(HdrTarget t, bool on, {void Function(String line)? onDiag}) {
    final b = calloc<Uint8>(24);
    try {
      _header(b, _typeSetAdvancedColor, 24, t);
      (b + 20).cast<Uint32>().value = on ? 1 : 0;
      final r = _setDeviceInfo(b);
      onDiag?.call('hdr: target ${t.id} → ${on ? 'on' : 'off'} (rc $r)');
      return r == 0;
    } catch (e) {
      onDiag?.call('hdr: set failed: $e');
      return false;
    } finally {
      calloc.free(b);
    }
  }

  static void _header(Pointer<Uint8> b, int type, int size, HdrTarget t) {
    (b + 0).cast<Uint32>().value = type;
    (b + 4).cast<Uint32>().value = size;
    (b + 8).cast<Uint32>().value = t.adapterLow;
    (b + 12).cast<Int32>().value = t.adapterHigh;
    (b + 16).cast<Uint32>().value = t.id;
  }
}
