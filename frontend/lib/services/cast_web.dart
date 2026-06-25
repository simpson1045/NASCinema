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

/// True once the Cast framework has initialized (Chrome/Edge). We gate the
/// button on THIS, not device presence — clicking opens the browser's device
/// picker (which lists devices or says none found), the standard Cast UX.
bool castReady() => _state() != 'UNAVAILABLE';

/// True once the framework is up and at least one Chromecast is on the network.
bool castDeviceAvailable() {
  final s = _state();
  return s != 'UNAVAILABLE' && s != 'NO_DEVICES_AVAILABLE';
}

bool castConnected() => _state() == 'CONNECTED';

/// Pops the device picker (if not already connected) and loads the media on the
/// receiver. [subUrl] '' means no subtitle track.
void castLoadMedia(String url, String contentType, String title, String subUrl) =>
    _castLoad(url, contentType, title, subUrl);
