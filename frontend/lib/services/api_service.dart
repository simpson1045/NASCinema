import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/extra.dart';
import '../models/home.dart';
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

  /// Server-composed home: featured set (for the hero) + rails. This is the same
  /// payload the Roku renders — the carousel home is just a different presenter.
  Future<HomeData> getHome() async {
    final r = await http.get(_u('/api/home')).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    return HomeData.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Re-scan the media folders on the server: add new files, prune deleted ones.
  /// Best-effort — if it's slow/unreachable the caller still reloads the list.
  Future<void> triggerScan() async {
    try {
      await http.post(_u('/api/scan')).timeout(const Duration(seconds: 180));
    } catch (_) {
      // scan keeps running server-side; the list reload still reflects progress
    }
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

  /// [client] declares playback capability to the decision engine: 'web'
  /// (browser codecs) or 'native' (libmpv — direct-plays everything).
  Future<
      ({
        String mode,
        String reason,
        String url,
        String? path,
        Map<String, dynamic> source,
        String? backdrop,
        String? logo,
        double resumePosition,
        String? resumeSubtitle,
      })> getPlay(int fileId, {String client = 'web'}) async {
    final r = await http
        .get(_u('/api/play/$fileId?client=$client'))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      mode: (d['mode'] ?? 'transcode').toString(),
      reason: (d['reason'] ?? '').toString(),
      url: (d['url'] ?? '').toString(),
      // Direct-play source path (native clients only): the wired renderer
      // reads the file straight off the NAS — the proven flawless byte path.
      path: d['path'] as String?,
      source: (d['source'] as Map<String, dynamic>?) ?? const {},
      backdrop: d['backdrop'] as String?,
      logo: d['logo'] as String?,
      resumePosition: (d['resume_position'] as num?)?.toDouble() ?? 0.0,
      resumeSubtitle: d['resume_subtitle'] as String?,
    );
  }

  /// Save where the user is in a file (+ which subtitle is on) so the next play
  /// resumes there. Best-effort — never throws into the playback path.
  Future<void> saveProgress(int fileId, double position, String? subtitle) async {
    try {
      await http
          .put(
            _u('/api/progress/$fileId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'position': position, 'subtitle': subtitle}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // ignore — a missed save just means a slightly stale resume point
    }
  }

  /// Converted spans (seconds) for the scrubber, plus the film's duration.
  Future<({double duration, List<List<double>> ranges})> getCached(
      int fileId) async {
    final r = await http
        .get(_u('/api/stream/$fileId/cached'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    final ranges = ((d['ranges'] ?? []) as List)
        .map((e) =>
            (e as List).map((n) => (n as num).toDouble()).toList())
        .toList();
    return (
      duration: (d['duration'] as num?)?.toDouble() ?? 0,
      ranges: ranges,
    );
  }

  /// Downloaded subtitle tracks for a file, plus the saved sync offset.
  Future<({List<Map<String, dynamic>> subtitles, double offset})> getSubtitles(
      int fileId) async {
    final r = await http
        .get(_u('/api/subtitles/$fileId'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return (subtitles: <Map<String, dynamic>>[], offset: 0.0);
    }
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      subtitles: ((d['subtitles'] ?? []) as List).cast<Map<String, dynamic>>(),
      offset: (d['offset'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Persist the per-file subtitle sync offset (seconds).
  Future<void> setSubtitleOffset(int fileId, double seconds) async {
    await http
        .put(
          _u('/api/subtitles/$fileId/offset'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'seconds': seconds}),
        )
        .timeout(const Duration(seconds: 10));
  }

  /// Search OpenSubtitles for this file (exact hash, then title/year).
  Future<List<Map<String, dynamic>>> searchSubtitles(
      int fileId, String lang) async {
    final r = await http
        .get(_u('/api/subtitles/$fileId/search?lang=$lang'))
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw Exception('Search failed (HTTP ${r.statusCode})');
    }
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return ((d['results'] ?? []) as List).cast<Map<String, dynamic>>();
  }

  /// Download a chosen subtitle; returns {id, label, lang, url}.
  Future<Map<String, dynamic>> downloadSubtitle(
      int fileId, int osFileId, String language) async {
    final r = await http
        .post(
          _u('/api/subtitles/$fileId/download'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'os_file_id': osFileId, 'language': language}),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw Exception('Download failed (HTTP ${r.statusCode})');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> updateMovie(
    int id, {
    String? blurayUrl,
    String? trailerYoutube,
  }) async {
    // Send only the field(s) being changed — the backend leaves omitted ones be.
    final body = <String, dynamic>{};
    if (blurayUrl != null) body['bluray_url'] = blurayUrl;
    if (trailerYoutube != null) body['trailer_youtube'] = trailerYoutube;
    final r = await http
        .patch(
          _u('/api/movies/$id'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw Exception('Backend returned HTTP ${r.statusCode}');
    }
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
