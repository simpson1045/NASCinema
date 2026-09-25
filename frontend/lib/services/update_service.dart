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
  /// - Windows: extract, hand off to an update script (robocopy with
  ///   retries), relaunch — see [_applyWindowsUpdate].
  static Future<void> applyUpdate(String filePath) async {
    if (Platform.isAndroid) {
      await OpenFilex.open(filePath);
    } else if (Platform.isWindows) {
      await _applyWindowsUpdate(filePath);
    }
  }

  /// Lifted verbatim (names aside) from NASRadio's updater, which already
  /// updates on Matt's machines. NASCinema's earlier copies (a detached
  /// .bat, then a PowerShell helper, then conhost --headless) all failed on
  /// ELKO for the reason NASRadio's comments below record: a console-less
  /// child can't run the script. Keep the two apps in sync.
  /// Windows-specific update: extract zip, write batch script, relaunch.
  ///
  /// The hard part of a Windows in-place update is overwriting the
  /// running .exe and its locked DLLs. Windows holds an exclusive
  /// lock on a running executable, so any copy attempt before the
  /// process has fully released its handles silently skips those
  /// files — and the restart launches the OLD binary unchanged
  /// (which is exactly the "update banner stays after install" bug
  /// Matt was hitting).
  ///
  /// The old script used `xcopy /Y` with a 2-second `timeout` before
  /// the copy. That was too short on a typical desktop with audio
  /// services + several Flutter plugin DLLs to tear down, and
  /// xcopy's exit code doesn't reliably surface "couldn't open
  /// destination" — it returned 0 and the restart launched the
  /// stale build. Replaced with `robocopy /R:30 /W:1` (30 retries,
  /// 1s wait — handles transient locks for up to 30s), a longer
  /// initial wait, and a log file so the next "update didn't take"
  /// can be diagnosed by looking at %TEMP%\\nascinema-update.log.
  static Future<void> _applyWindowsUpdate(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;
    final tempDir = (await getTemporaryDirectory()).path;
    final extractDir = '$tempDir\\nascinema-update-extracted';

    // Extract zip
    final zipBytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    final extractDirObj = Directory(extractDir);
    if (await extractDirObj.exists()) {
      await extractDirObj.delete(recursive: true);
    }
    await extractDirObj.create(recursive: true);

    for (final file in archive) {
      final outPath = '$extractDir\\${file.name}';
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    // Write update batch script.
    //
    // robocopy notes:
    //   /E  — copy subdirs including empty
    //   /NFL /NDL /NP — suppress per-file/dir/percent spam in the log
    //   /R:30 /W:1 — 30 retries with 1s between (handles "running
    //                exe still has the .exe file locked" by simply
    //                waiting it out; total worst-case wait ~30s)
    //   /XF nascinema-update.bat nascinema-update.log — don't try to
    //                copy our own running script/log over itself
    // robocopy exit codes 0..7 are success (0=nothing copied, 1=files
    // copied OK, 2-7=harmless extras); 8+ are real errors. The bat
    // checks `if errorlevel 8` so a partial-failure surfaces.
    final batPath = '$tempDir\\nascinema-update.bat';
    final logPath = '$tempDir\\nascinema-update.log';
    final exeName = File(exePath).uri.pathSegments.last;
    final batContent = '''@echo off
setlocal enabledelayedexpansion
echo === NASCinema update started at %DATE% %TIME% === > "$logPath"
echo Updating NASCinema...
echo Waiting for nascinema.exe to fully exit and release file locks...
echo Wait phase starting >> "$logPath"
REM Poll for the process exiting. tasklist is cheap (~10ms) and lets
REM us proceed the instant the lock is released instead of guessing
REM with a fixed sleep. Cap at 30s so a wedged process can't hang
REM the update forever.
set /a _waited=0
:wait_for_exit
tasklist /FI "IMAGENAME eq $exeName" 2>nul | find /I "$exeName" >nul
if errorlevel 1 goto exit_done
if !_waited! GEQ 30 goto exit_timeout
timeout /t 1 /nobreak >nul
set /a _waited+=1
goto wait_for_exit
:exit_timeout
echo WARN: $exeName still running after 30s, attempting copy anyway >> "$logPath"
:exit_done
echo Exit-wait done after !_waited!s >> "$logPath"

echo Copying new files from "$extractDir" to "$installDir" ...
echo robocopy starting >> "$logPath"
robocopy "$extractDir" "$installDir" /E /NFL /NDL /NP /R:30 /W:1 ^
  /XF "nascinema-update.bat" "nascinema-update.log" >> "$logPath" 2>&1
set _rc=!errorlevel!
echo robocopy exit code: !_rc! >> "$logPath"

REM robocopy: 0..7 success, 8+ failure.
if !_rc! GEQ 8 (
  echo === UPDATE FAILED — see "$logPath" === >> "$logPath"
  echo NASCinema update FAILED — see "$logPath" for details.
  echo Press any key to close...
  pause >nul
  goto cleanup
)

echo === UPDATE OK === >> "$logPath"
echo Launching updated NASCinema...
start "" "$installDir\\$exeName"

:cleanup
rmdir /S /Q "$extractDir" 2>nul
REM Intentionally NOT deleting "$logPath" — kept so the user can
REM inspect the most recent update attempt if anything looked off.
del "$batPath"
''';

    await File(batPath).writeAsString(batContent);

    // Launch the batch script through `start` so it gets a REAL console.
    // ProcessStartMode.detached spawns cmd console-less, and in that
    // state the script's `tasklist | find` pipeline wedges forever —
    // find never sees EOF, the window sits empty until the user
    // Ctrl+C's it (which killed find, faked "app exited", and let the
    // update proceed — the bug every desktop update showed for months).
    // `start` allocates a fresh console: pipelines work, the user can
    // actually see the progress echoes, and the window closes itself.
    await Process.start(
      'cmd',
      ['/c', 'start', 'NASCinema Update', 'cmd', '/c', batPath],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
