import 'dart:js_interop';

// Bindings to the Cast glue defined in web/index.html (CAF sender SDK).
@JS('nascinemaCastState')
external String _castState();

@JS('nascinemaCastLoad')
external void _castLoad(
    String url, String contentType, String title, String subUrl);

String _state() {
  try {
    return _castState();
  } catch (_) {
    return 'UNAVAILABLE'; // SDK not loaded yet
  }
}

/// True once the framework is up and at least one Chromecast is on the network
/// — gates whether we even show the cast button.
bool castDeviceAvailable() {
  final s = _state();
  return s != 'UNAVAILABLE' && s != 'NO_DEVICES_AVAILABLE';
}

bool castConnected() => _state() == 'CONNECTED';

/// Pops the device picker (if not already connected) and loads the media on the
/// receiver. [subUrl] '' means no subtitle track.
void castLoadMedia(String url, String contentType, String title, String subUrl) =>
    _castLoad(url, contentType, title, subUrl);
