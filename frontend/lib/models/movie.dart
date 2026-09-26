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
    this.blurayUrl,
    this.trailerYoutube,
    this.imdbRating,
    this.rtScore,
    this.certification,
    this.metacritic,
    this.popularity,
    this.collectionName,
    this.logo,
    this.logoSubtitle,
    this.trailerUrl,
    this.trailerReady = false,
    this.trailerBars,
    this.resumePosition,
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
  final String? blurayUrl;
  final String? trailerYoutube; // manual trailer override (YouTube URL/key)
  final double? imdbRating; // external ratings (OMDb), null if unknown
  final int? rtScore; // Rotten Tomatoes %, 0–100
  final String? certification; // content rating: PG-13, R … (region setting)
  final int? metacritic; // Metacritic, 0–100
  final double? popularity; // TMDB popularity
  final String? collectionName; // e.g. "Harry Potter Collection"
  final String? logo; // clearlogo URL — featured items only
  // Set when [logo] is the franchise's shared wordmark: this movie's part of
  // the title, printed under the logo ("VIII · The Big Freeze").
  final String? logoSubtitle;
  final String? trailerUrl; // /api/movies/{id}/trailer?v=… — featured only
  final bool trailerReady; // backend has the trailer cached
  /// Letterbox bars baked into the cached trailer, as fractions of a 16:9
  /// screen (null = not measured yet / full-frame). Featured items only.
  final TrailerBars? trailerBars;
  final double? resumePosition; // seconds — Continue Watching items only

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
        blurayUrl: j['bluray_url'] as String?,
        trailerYoutube: j['trailer_youtube'] as String?,
        imdbRating: (j['imdb_rating'] as num?)?.toDouble(),
        rtScore: (j['rt_score'] as num?)?.toInt(),
        certification: j['certification'] as String?,
        metacritic: (j['metacritic'] as num?)?.toInt(),
        popularity: (j['popularity'] as num?)?.toDouble(),
        collectionName: j['collection_name'] as String?,
        logo: j['logo'] as String?,
        logoSubtitle: j['logo_subtitle'] as String?,
        trailerUrl: j['trailer_url'] as String?,
        trailerReady: j['trailer_ready'] == true,
        trailerBars: j['trailer_bars'] is Map
            ? TrailerBars.fromJson(j['trailer_bars'] as Map<String, dynamic>)
            : null,
        resumePosition: (j['resume_position'] as num?)?.toDouble(),
      );

  /// How far into the movie the resume point is, 0..1 (null if not started).
  double? get progress {
    final pos = resumePosition;
    if (pos == null || runtime == null || runtime == 0) return null;
    return (pos / (runtime! * 60)).clamp(0.0, 1.0);
  }

  /// TMDB CDN poster URL, or null if unmatched.
  String? posterUrl({String size = 'w342'}) =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/$size$posterPath';

  /// TMDB CDN backdrop URL, or null if unmatched.
  String? backdropUrl({String size = 'w1280'}) =>
      backdropPath == null
          ? null
          : 'https://image.tmdb.org/t/p/$size$backdropPath';

  /// The pinned Blu-ray.com release, or a search for this title.
  String get blurayLink {
    if (blurayUrl != null && blurayUrl!.isNotEmpty) return blurayUrl!;
    final q = Uri.encodeComponent('$title ${year ?? ''}'.trim());
    return 'https://www.blu-ray.com/search/?quicksearch=1'
        '&quicksearch_keyword=$q&section=bluraymovies';
  }

  bool get blurayPinned => blurayUrl != null && blurayUrl!.isNotEmpty;

  String? get runtimeLabel {
    if (runtime == null || runtime == 0) return null;
    final h = runtime! ~/ 60;
    final m = runtime! % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// A short quality badge from the primary file, e.g. "4K HDR" / "1080p".
  ///
  /// Judged by the picture's 16:9-equivalent height, not the raw height: a
  /// scope film stored cropped at 1920x800 is 1080p (not "720p"), 3840x1600
  /// is 4K, and a 4:3 2880x2160 special is 4K too.
  String? get qualityBadge {
    if (resolution == null) return null;
    final parts = resolution!.split('x');
    final w = parts.length == 2 ? int.tryParse(parts.first) : null;
    final raw = int.tryParse(parts.last);
    final h = (w == null || raw == null)
        ? raw
        : (w * 9 / 16).round() > raw ? (w * 9 / 16).round() : raw;
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

/// Black bars baked into a trailer, as fractions of a 16:9 screen's height.
class TrailerBars {
  const TrailerBars({required this.top, required this.bottom});

  final double top;
  final double bottom;

  factory TrailerBars.fromJson(Map<String, dynamic> j) => TrailerBars(
        top: (j['top'] as num?)?.toDouble() ?? 0,
        bottom: (j['bottom'] as num?)?.toDouble() ?? 0,
      );
}
