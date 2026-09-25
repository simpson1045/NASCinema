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

    // Hand off to a hidden PowerShell helper that waits for this process to
    // exit (a running .exe holds an exclusive lock), copies the new files in,
    // relaunches, and cleans up. It used to be a .bat, but a detached cmd has
    // no console: every console tool it ran (tasklist/find) opened its own
    // window and `find` sat reading that window's keyboard until Ctrl+C.
    // PowerShell needs no console, and robocopy runs with a hidden window.
    final ps1Path = '$tempDir\\nascinema-update.ps1';
    String psq(String s) => "'${s.replaceAll("'", "''")}'";
    final vars = [
      '\$AppPid = $pid',
      '\$Exe = ${psq(exePath)}',
      '\$InstallDir = ${psq(installDir)}',
      '\$Extract = ${psq(extractDir)}',
      '\$Zip = ${psq(zipPath)}',
      '\$LogPath = ${psq('$tempDir\\nascinema-update.log')}',
    ].join('\r\n');
    const body = r'''
function Log($m) { Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format s)  $m" }
Set-Content -LiteralPath $LogPath -Value "=== NASCinema update started $(Get-Date -Format s) ==="
Wait-Process -Id $AppPid -Timeout 30 -ErrorAction SilentlyContinue
Log "app exited; copying"
# robocopy /R:30 /W:1 rides out transient locks; exit codes >= 8 are failures.
$rcArgs = @("`"$Extract`"", "`"$InstallDir`"", '/E', '/NFL', '/NDL', '/NP', '/R:30', '/W:1', "/LOG+:`"$LogPath`"")
$p = Start-Process robocopy -ArgumentList $rcArgs -WindowStyle Hidden -Wait -PassThru
if ($p.ExitCode -lt 8) { Log "=== UPDATE OK (robocopy $($p.ExitCode)) ===" } else { Log "=== UPDATE FAILED (robocopy $($p.ExitCode)) ===" }
Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
Remove-Item -LiteralPath $Extract -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
''';

    await File(ps1Path).writeAsString('$vars\r\n$body');
    // Through `conhost --headless`: Dart's detached mode starts the child with
    // NO console, and powershell.exe silently exits without one — the 0.4.2
    // helper never ran (verified on ELKO: detached = didn't run, conhost
    // --headless = ran). conhost gives it a hidden console; nothing shows.
    await Process.start(
        'conhost.exe',
        [
          '--headless',
          'powershell',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          ps1Path,
        ],
        mode: ProcessStartMode.detached);
    exit(0);
  }
}
