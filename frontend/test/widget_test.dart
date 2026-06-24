import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/services/api_service.dart';

void main() {
  test('HealthStatus parses the backend /api/health payload', () {
    final h = HealthStatus.fromJson({
      'version': '0.0.0',
      'db': true,
      'ffmpeg': true,
      'ffprobe': false,
      'media_dirs': 2,
    });
    expect(h.version, '0.0.0');
    expect(h.db, isTrue);
    expect(h.ffmpeg, isTrue);
    expect(h.ffprobe, isFalse);
    expect(h.mediaDirs, 2);
  });
}
