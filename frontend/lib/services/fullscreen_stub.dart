// Web (and anywhere without dart:io): fullscreen is the browser's own F11, so
// these are no-ops and the desktop-only UI is hidden.
bool get isDesktop => false;

Future<void> initWindowForDesktop() async {}

Future<void> toggleFullscreen() async {}
