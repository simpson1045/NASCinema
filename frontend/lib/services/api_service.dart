import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/extra.dart';
import '../models/movie.dart';
import '../models/movie_file.dart';
import '../models/video.dart';

/// Parsed result of GET /api/health.
class HealthStatus {
  HealthStatus({
    required this.version,
    required this.db,
    required this.ffmpeg,
    required this.ffprobe,
    required this.mediaDirs,
  });

  final String version;
  final bool db;
  final bool ffmpeg;
  final bool ffprobe;
  final int mediaDirs;

  factory HealthStatus.fromJson(Map<String, dynamic> j) => HealthStatus(
        version: (j['version'] ?? '?').toString(),
        db: j['db'] == true,
        ffmpeg: j['ffmpeg'] == true,
        ffprobe: j['ffprobe'] == true,
        mediaDirs: (j['media_dirs'] ?? 0) as int,
      );
}

/// Thin client over the NASCinema backend. Base URL is supplied at runtime.
class ApiService {
  ApiService(this.baseUrl);

  final String baseUrl;

  Uri _u(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<HealthStatus> health() async {
    final r = await http
        .get(_u('/api/health'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    return HealthStatus.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<Movie>> listMovies() async {
    final r = await http.get(_u('/api/movies')).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['movies'] as List)
        .map((e) => Movie.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({List<MovieFile> files, List<Extra> extras})> getMovieDetail(
      int id) async {
    final r =
        await http.get(_u('/api/movies/$id')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final files = ((data['files'] ?? []) as List)
        .map((e) => MovieFile.fromJson(e as Map<String, dynamic>))
        .toList();
    final extras = ((data['extras'] ?? []) as List)
        .map((e) => Extra.fromJson(e as Map<String, dynamic>))
        .toList();
    return (files: files, extras: extras);
  }

  Future<List<Video>> getMovieVideos(int id) async {
    final r = await http
        .get(_u('/api/movies/$id/videos'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return ((data['videos'] ?? []) as List)
        .map((e) => Video.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateExtra(int id, {String? title, String? type}) async {
    final r = await http
        .patch(
          _u('/api/extras/$id'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'title': ?title,
            'type': ?type,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
  }
}
