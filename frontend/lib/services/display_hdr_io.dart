import 'dart:io';

/// Is HDR switched on for a display? Windows records it per monitor under
/// GraphicsDrivers\MonitorDataStore (`HDREnabled` on current builds,
/// `AdvancedColorEnabled` on older ones). Other platforms: false for now —
/// phones play trailers in a texture that can't show HDR anyway.
/// Any error → false (SDR is always safe).
Future<bool> displayHdrActive() async {
  if (!Platform.isWindows) return false;
  try {
    final r = await Process.run('reg', [
      'query',
      r'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorDataStore',
      '/s',
    ]).timeout(const Duration(seconds: 5));
    if (r.exitCode != 0) return false;
    return RegExp(r'(HDREnabled|AdvancedColorEnabled)\s+REG_DWORD\s+0x0*1\b')
        .hasMatch(r.stdout.toString());
  } catch (_) {
    return false;
  }
}
