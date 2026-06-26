import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Info about an available update.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.changelog,
    required this.sizeBytes,
    required this.releasedAt,
  });

  final String version;
  final int buildNumber;
  final String changelog;
  final int sizeBytes;
  final String releasedAt;
}

/// Checks, downloads, and applies app updates served by the backend
/// (`/api/update/*`, populated by `backend/release.bat`).
class UpdateService {
  UpdateService._();

  static String _base(String baseUrl) => baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Returns [UpdateInfo] if the server has a newer build than this one, else
  /// null (up to date, no manifest, or unreachable — all non-fatal).
  static Future<UpdateInfo?> checkForUpdate(String baseUrl) async {
    try {
      final r = await http
          .get(Uri.parse('${_base(baseUrl)}/api/update/check'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      final serverVersion = data['version'] as String? ?? '0.0.0';
      final serverBuild = (data['build_number'] as num?)?.toInt() ?? 0;
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (!_isNewer(serverVersion, serverBuild, info.version, currentBuild)) {
        return null;
      }

      final sizeKey = Platform.isWindows
          ? 'windows_size'
          : Platform.isLinux
              ? 'linux_size'
              : 'android_size';
      return UpdateInfo(
        version: serverVersion,
        buildNumber: serverBuild,
        changelog: (data['changelog'] ?? '').toString(),
        sizeBytes: (data[sizeKey] as num?)?.toInt() ?? 0,
        releasedAt: (data['released_at'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[Update] check failed: $e');
      return null;
    }
  }

  /// Semver first; build number breaks ties (same X.Y.Z, higher +BUILD = update).
  static bool _isNewer(String sv, int sb, String cv, int cb) {
    final s = sv.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final c = cv.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (s.length < 3) {
      s.add(0);
    }
    while (c.length < 3) {
      c.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (s[i] > c[i]) return true;
      if (s[i] < c[i]) return false;
    }
    return sb > cb;
  }

  /// Download the artifact for this platform, reporting 0..1 progress.
  static Future<String> downloadUpdate(
    String baseUrl, {
    required void Function(double progress) onProgress,
  }) async {
    final String platform;
    final String ext;
    if (Platform.isWindows) {
      platform = 'windows';
      ext = '.zip';
    } else if (Platform.isLinux) {
      platform = 'linux';
      ext = '.tar.xz';
    } else {
      platform = 'android';
      ext = '.apk';
    }

    final client = http.Client();
    try {
      final response = await client.send(http.Request(
          'GET', Uri.parse('${_base(baseUrl)}/api/update/download/$platform')));
      final contentLength = response.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/nascinema-update$ext';
      final sink = File(filePath).openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) onProgress(received / contentLength);
      }
      await sink.close();
      return filePath;
    } finally {
      client.close();
    }
  }

  /// Apply the downloaded update.
  /// - Android: hand the APK to the system installer.
  /// - Windows: extract the zip, write a script that waits for the exe to
  ///   release its locks, robocopies the new files in, and relaunches.
  static Future<void> applyUpdate(String filePath) async {
    if (Platform.isAndroid) {
      await OpenFilex.open(filePath);
    } else if (Platform.isWindows) {
      await _applyWindowsUpdate(filePath);
    }
  }

  static Future<void> _applyWindowsUpdate(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;
    final tempDir = (await getTemporaryDirectory()).path;
    final extractDir = '$tempDir\\nascinema-update-extracted';
    final exeName = File(exePath).uri.pathSegments.last;

    // Extract the zip.
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final extractObj = Directory(extractDir);
    if (await extractObj.exists()) await extractObj.delete(recursive: true);
    await extractObj.create(recursive: true);
    for (final f in archive) {
      final outPath = '$extractDir\\${f.name}';
      if (f.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    // A running .exe holds an exclusive lock, so wait for it to exit before
    // copying (robocopy /R:30 /W:1 also rides out transient locks). Then relaunch.
    final batPath = '$tempDir\\nascinema-update.bat';
    final logPath = '$tempDir\\nascinema-update.log';
    final bat = '''@echo off
setlocal enabledelayedexpansion
echo === NASCinema update started at %DATE% %TIME% === > "$logPath"
set /a _waited=0
:wait_for_exit
tasklist /FI "IMAGENAME eq $exeName" 2>nul | find /I "$exeName" >nul
if errorlevel 1 goto exit_done
if !_waited! GEQ 30 goto exit_done
timeout /t 1 /nobreak >nul
set /a _waited+=1
goto wait_for_exit
:exit_done
echo Exit-wait done after !_waited!s >> "$logPath"
robocopy "$extractDir" "$installDir" /E /NFL /NDL /NP /R:30 /W:1 ^
  /XF "nascinema-update.bat" "nascinema-update.log" >> "$logPath" 2>&1
set _rc=!errorlevel!
echo robocopy exit code: !_rc! >> "$logPath"
if !_rc! GEQ 8 (
  echo === UPDATE FAILED — see "$logPath" === >> "$logPath"
  echo NASCinema update FAILED — see "$logPath".
  pause >nul
  goto cleanup
)
echo === UPDATE OK === >> "$logPath"
start "" "$installDir\\$exeName"
:cleanup
rmdir /S /Q "$extractDir" 2>nul
del "$batPath"
''';

    await File(batPath).writeAsString(bat);
    await Process.start('cmd', ['/c', batPath],
        mode: ProcessStartMode.detached);
    exit(0);
  }
}
