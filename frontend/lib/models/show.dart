import 'movie_file.dart';

String? _tmdb(String? path, String size) => path == null
    ? null
    : (path.startsWith('http') ? path : 'https://image.tmdb.org/t/p/$size$path');

/// A TV show as the list/rails see it.
class Show {
  Show({
    required this.id,
    required this.title,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.genres = const [],
    this.rating,
    this.certification,
    this.status,
    this.seasonCount = 0,
    this.episodeCount = 0,
  });

  final int id;
  final String title;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final List<String> genres;
  final double? rating;
  final String? certification;
  final String? status;
  final int seasonCount;
  final int episodeCount;

  String? posterUrl({String size = 'w342'}) => _tmdb(posterPath, size);
  String? backdropUrl({String size = 'w1280'}) => _tmdb(backdropPath, size);

  factory Show.fromJson(Map<String, dynamic> j) => Show(
        id: j['id'] as int,
        title: (j['title'] ?? '').toString(),
        year: j['year'] as int?,
        overview: j['overview'] as String?,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        genres: ((j['genres'] ?? const []) as List).map((e) => e.toString()).toList(),
        rating: (j['rating'] as num?)?.toDouble(),
        certification: j['certification'] as String?,
        status: j['status'] as String?,
        seasonCount: (j['season_count'] ?? 0) as int,
        episodeCount: (j['episode_count'] ?? 0) as int,
      );
}

class ShowSeason {
  ShowSeason({required this.number, required this.name, this.episodeCount = 0});

  final int number; // 0 = Specials
  final String name;
  final int episodeCount;

  factory ShowSeason.fromJson(Map<String, dynamic> j) => ShowSeason(
        number: j['season_number'] as int,
        name: (j['name'] ?? '').toString(),
        episodeCount: (j['episode_count'] ?? 0) as int,
      );
}

class Episode {
  Episode({
    required this.id,
    required this.season,
    this.number,
    this.numberEnd,
    this.title,
    this.overview,
    this.stillPath,
    this.airDate,
    this.runtime,
    this.files = const [],
    this.position = 0,
    this.duration = 0,
    this.watched = false,
  });

  final int id;
  final int season;
  final int? number;
  final int? numberEnd;
  final String? title;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final int? runtime; // minutes
  final List<MovieFile> files;
  final double position;
  final double duration;
  final bool watched;

  String? stillUrl({String size = 'w500'}) => _tmdb(stillPath, size);

  /// "S5 · E17", "S1 · E1–2", "Special".
  String get code {
    if (number == null) return season == 0 ? 'Special' : 'S$season';
    final e = numberEnd != null ? '$number–$numberEnd' : '$number';
    return season == 0 ? 'Special $e' : 'S$season · E$e';
  }

  String get displayTitle => title ?? code;

  /// 0..1 when partly watched, null otherwise.
  double? get progress => (!watched && duration > 0 && position >= 30)
      ? (position / duration).clamp(0.0, 1.0)
      : null;

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as int,
        season: j['season_number'] as int,
        number: j['episode_number'] as int?,
        numberEnd: j['episode_end'] as int?,
        title: j['title'] as String?,
        overview: j['overview'] as String?,
        stillPath: j['still_path'] as String?,
        airDate: j['air_date'] as String?,
        runtime: j['runtime'] as int?,
        files: ((j['files'] ?? const []) as List)
            .map((e) => MovieFile.fromJson(e as Map<String, dynamic>))
            .toList(),
        position: ((j['position'] ?? 0) as num).toDouble(),
        duration: ((j['duration'] ?? 0) as num).toDouble(),
        watched: j['watched'] == true,
      );
}

/// One show's page: its seasons, every episode and what to play next.
class ShowDetail {
  ShowDetail({
    required this.show,
    this.logo,
    this.seasons = const [],
    this.episodes = const [],
    this.nextUp,
  });

  final Show show;
  final String? logo;
  final List<ShowSeason> seasons;
  final List<Episode> episodes;
  final Episode? nextUp;

  factory ShowDetail.fromJson(Map<String, dynamic> j) => ShowDetail(
        show: Show.fromJson(j),
        logo: j['logo'] as String?,
        seasons: ((j['seasons'] ?? const []) as List)
            .map((e) => ShowSeason.fromJson(e as Map<String, dynamic>))
            .toList(),
        episodes: ((j['episodes'] ?? const []) as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextUp: j['next_up'] is Map
            ? Episode.fromJson(j['next_up'] as Map<String, dynamic>)
            : null,
      );
}

/// A show you're partway through + the episode to play next.
class UpNext {
  UpNext({required this.show, required this.episode});

  final Show show;
  final Episode episode;

  factory UpNext.fromJson(Map<String, dynamic> j) => UpNext(
        show: Show.fromJson(j['show'] as Map<String, dynamic>),
        episode: Episode.fromJson(j['episode'] as Map<String, dynamic>),
      );
}
