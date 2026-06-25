// Non-web fallback: no Chromecast sender off the web build. The native ELKO
// app IS the renderer, so it doesn't cast.
bool castDeviceAvailable() => false;
bool castConnected() => false;
void castLoadMedia(String url, String contentType, String title, String subUrl) {}
