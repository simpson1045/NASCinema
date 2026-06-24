class Movie {
  Movie({
    required this.id,
    required this.title,
    this.year,
    this.rating,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.genres = const [],
    this.runtime,
    this.tmdbId,
    this.fileCount = 0,
    this.resolution,
    this.videoCodec,
    this.hdr = false,
  });

  final int id;
  final String title;
  final int? year;
  final double? rating;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final List<String> genres;
  final int? runtime;
  final int? tmdbId;
  final int fileCount;
  final String? resolution;
  final String? videoCodec;
  final bool hdr;

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: j['id'] as int,
        title: (j['title'] ?? '?').toString(),
        year: j['year'] as int?,
        rating: (j['rating'] as num?)?.toDouble(),
        overview: j['overview'] as String?,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        genres:
            (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        runtime: j['runtime'] as int?,
        tmdbId: j['tmdb_id'] as int?,
        fileCount: (j['file_count'] ?? 0) as int,
        resolution: j['resolution'] as String?,
        videoCodec: j['video_codec'] as String?,
        hdr: j['hdr'] == true,
      );

  /// TMDB CDN poster URL, or null if unmatched.
  String? posterUrl({String size = 'w342'}) =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/$size$posterPath';

  /// TMDB CDN backdrop URL, or null if unmatched.
  String? backdropUrl({String size = 'w1280'}) =>
      backdropPath == null
          ? null
          : 'https://image.tmdb.org/t/p/$size$backdropPath';

  String? get runtimeLabel {
    if (runtime == null || runtime == 0) return null;
    final h = runtime! ~/ 60;
    final m = runtime! % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// A short quality badge from the primary file, e.g. "4K HDR" / "1080p".
  String? get qualityBadge {
    if (resolution == null) return null;
    final h = int.tryParse(resolution!.split('x').last);
    String label;
    if (h == null) {
      label = resolution!;
    } else if (h >= 2000) {
      label = '4K';
    } else if (h >= 1060) {
      label = '1080p';
    } else if (h >= 700) {
      label = '720p';
    } else {
      label = 'SD';
    }
    return hdr ? '$label HDR' : label;
  }
}
