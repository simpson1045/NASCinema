@echo off
REM NASCinema release packaging — builds Android + Windows in one shot and
REM stages them where the in-app updater serves from (backend\updates\).
REM
REM Usage:  backend\release.bat ^<version^> ^<build_number^>
REM Example: backend\release.bat 0.4.1 2
REM
REM Run this on a LOCAL-DISK checkout (ALPINE) — `flutter build windows` cannot
REM create plugin symlinks on the NAS share. Steps:
REM   1. Bump frontend\pubspec.yaml to VERSION+BUILD (must precede builds so the
REM      version is stamped into the APK / exe that PackageInfo reports)
REM   2. flutter build apk --release
REM   3. flutter build windows --release
REM   4. Copy the APK   -> backend\updates\nascinema-android.apk
REM   5. Zip the Windows Release folder -> backend\updates\nascinema-windows.zip
REM   6. Write backend\updates\version.json (version, build, date, sizes)
REM   7. Prepend a CHANGELOG.md stub for you to fill in
REM
REM Does NOT commit or tag — do that by hand after editing the CHANGELOG.

setlocal enabledelayedexpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set "VERSION=%~1"
set "BUILD=%~2"
set "ROOT=%~dp0.."
set "FRONTEND=%ROOT%\frontend"
set "UPDATES=%ROOT%\backend\updates"
set "APK_SRC=%FRONTEND%\build\app\outputs\flutter-apk\app-release.apk"
set "WIN_SRC=%FRONTEND%\build\windows\x64\runner\Release"
set "APK_DST=%UPDATES%\nascinema-android.apk"
set "WIN_DST=%UPDATES%\nascinema-windows.zip"
set "CHANGELOG=%ROOT%\CHANGELOG.md"
set "PUBSPEC=%FRONTEND%\pubspec.yaml"

echo.
echo === NASCinema release v%VERSION% (build %BUILD%) ===
echo.

REM Write UTF-8 WITHOUT a BOM throughout: PowerShell 5.x Set-Content -Encoding
REM UTF8 writes a BOM which breaks Python's json.load + CHANGELOG parsing.

echo [1/7] Bumping pubspec.yaml to %VERSION%+%BUILD%...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$existing = [IO.File]::ReadAllText('%PUBSPEC%', [Text.UTF8Encoding]::new($false));" ^
  "$new = $existing -replace '(?m)^version:.*$', 'version: %VERSION%+%BUILD%';" ^
  "[IO.File]::WriteAllText('%PUBSPEC%', $new, [Text.UTF8Encoding]::new($false))" || exit /b 1

echo [1.5/7] flutter clean + pub get (release builds reuse a stale Dart
echo         snapshot otherwise — exe relinks but app.so/dex stays old)...
pushd "%FRONTEND%"
call flutter clean || (popd ^& exit /b 1)
call flutter pub get || (popd ^& exit /b 1)
popd

echo [2/7] flutter build apk --release ...
pushd "%FRONTEND%"
call flutter build apk --release || (popd ^& exit /b 1)
popd

REM The `jni` plugin's Windows native links against the JDK's jvm.lib; the
REM machine's default JAVA_HOME is a 32-bit JDK, so an x64 build fails with
REM "machine type x86 conflicts with x64". Point at an x64 JDK for this step.
set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.10.7-hotspot"
echo [3/7] flutter build windows --release (JAVA_HOME=%JAVA_HOME%) ...
pushd "%FRONTEND%"
call flutter build windows --release || (popd ^& exit /b 1)
popd

echo [3.5/7] flutter build web (clean wiped build\web — restore the served UI)...
pushd "%FRONTEND%"
call flutter build web --pwa-strategy=none || (popd ^& exit /b 1)
popd

if not exist "%APK_SRC%" (
  echo ERROR: APK not found at %APK_SRC% after build.
  exit /b 1
)
if not exist "%WIN_SRC%\data\app.so" (
  echo ERROR: Windows build not found at %WIN_SRC% after build.
  exit /b 1
)

echo [4/7] Copying APK...
copy /Y "%APK_SRC%" "%APK_DST%" >nul || exit /b 1
REM Also serve it at the friendly URL (/nascinema.apk) for manual installs.
copy /Y "%APK_SRC%" "%FRONTEND%\build\web\nascinema.apk" >nul

echo [5/7] Zipping Windows build...
REM Compress-Archive can exit 0 while silently failing (e.g. nascinema.exe held
REM open by a running app). Force a Stop on error, then verify size below.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "try { Compress-Archive -Force -Path '%WIN_SRC%\*' -DestinationPath '%WIN_DST%' } catch { Write-Host 'ZIP FAILED:' $_.Exception.Message -ForegroundColor Red; exit 1 }" || exit /b 1

if not exist "%WIN_DST%" (
  echo ERROR: Windows zip %WIN_DST% not produced.
  exit /b 1
)

for %%A in ("%APK_DST%") do set "ANDROID_SIZE=%%~zA"
for %%A in ("%WIN_DST%") do set "WIN_SIZE=%%~zA"

if "%WIN_SIZE%"=="" (
  echo ERROR: Windows ZIP size is empty — zip was probably not produced.
  exit /b 1
)
if %WIN_SIZE% LSS 1024 (
  echo ERROR: Windows ZIP is only %WIN_SIZE% bytes — likely empty or corrupt.
  exit /b 1
)

echo [6/7] Writing version.json...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$today = (Get-Date -Format 'yyyy-MM-dd');" ^
  "$json = @{ version='%VERSION%'; build_number=[int]%BUILD%; released_at=$today; android_size=[long]%ANDROID_SIZE%; windows_size=[long]%WIN_SIZE% } | ConvertTo-Json;" ^
  "[IO.File]::WriteAllText('%UPDATES%\version.json', $json, [Text.UTF8Encoding]::new($false))" || exit /b 1

echo [7/7] Prepending CHANGELOG.md stub...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$today = (Get-Date -Format 'yyyy-MM-dd');" ^
  "$stub = \"## %VERSION% - $today`n- TODO: release notes`n`n\";" ^
  "$existing = [IO.File]::ReadAllText('%CHANGELOG%', [Text.UTF8Encoding]::new($false));" ^
  "[IO.File]::WriteAllText('%CHANGELOG%', ($stub + $existing), [Text.UTF8Encoding]::new($false))" || exit /b 1

echo.
echo Done.
echo   APK:     %ANDROID_SIZE% bytes  -^> %APK_DST%
echo   ZIP:     %WIN_SIZE% bytes  -^> %WIN_DST%
echo   Version: %VERSION% (build %BUILD%)
echo.
echo Next: edit CHANGELOG.md (replace the TODO), then commit.
echo.

endlocal
exit /b 0

:usage
echo Usage: backend\release.bat ^<version^> ^<build_number^>
echo Example: backend\release.bat 0.4.1 2
exit /b 1
