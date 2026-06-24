import 'package:shared_preferences/shared_preferences.dart';

/// Persists the backend address on-device — configurable per install, no
/// recompile. The URL isn't a secret, so plain preferences (works in any web
/// context, unlike secure storage) is the right tool. Token storage will use a
/// proper secure store when auth lands.
class ServerConfig {
  static const _key = 'server_url';

  Future<String?> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, url.trim());
    } catch (_) {
      // Persisting the URL is best-effort; never block connecting on it.
    }
  }
}
