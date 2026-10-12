import 'franchise.dart';
import 'movie.dart';
import 'show.dart';

/// One horizontal row on the home screen (Continue Watching, Popular, a genre…).
class HomeRail {
  HomeRail({
    required this.key,
    required this.title,
    required this.movies,
    this.franchises = const [],
    this.shows = const [],
    this.upNext = const [],
  });

  final String key;
  final String title;
  final List<Movie> movies;
  // The Franchises row carries franchise tiles instead of movies.
  final List<Franchise> franchises;
  // TV: the TV Shows row (posters) and Up Next (the episode to play next).
  final List<Show> shows;
  final List<UpNext> upNext;

  bool get isFranchises => franchises.isNotEmpty;
  bool get isShows => shows.isNotEmpty;
  bool get isUpNext => upNext.isNotEmpty;
  bool get isTv => isShows || isUpNext;
  int get length => isFranchises
      ? franchises.length
      : isShows
          ? shows.length
          : isUpNext
              ? upNext.length
              : movies.length;

  factory HomeRail.fromJson(Map<String, dynamic> j) => HomeRail(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        movies: ((j['movies'] ?? const []) as List)
            .map((e) => Movie.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The whole server-composed home: a featured set (for the hero) + the rails.
class HomeData {
  HomeData({required this.featured, required this.rails, this.collections = const []});

  final List<Movie> featured;
  final List<HomeRail> rails;
  final List<Franchise> collections;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
        featured: ((j['featured'] ?? const []) as List)
            .map((e) => Movie.fromJson(e as Map<String, dynamic>))
            .toList(),
        rails: ((j['rails'] ?? const []) as List)
            .map((e) => HomeRail.fromJson(e as Map<String, dynamic>))
            .toList(),
        collections: ((j['collections'] ?? const []) as List)
            .map((e) => Franchise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
