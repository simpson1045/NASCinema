import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the backend address on-device — configurable per install, no
/// recompile, nothing hardcoded (mirrors NASRadio's login-screen gear).
class ServerConfig {
  static const _key = 'server_url';
  static const _storage = FlutterSecureStorage();

  Future<String?> get() => _storage.read(key: _key);

  Future<void> set(String url) => _storage.write(key: _key, value: url.trim());
}
