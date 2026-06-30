import 'movie.dart';

/// One horizontal row on the home screen (Continue Watching, Popular, a genre…).
class HomeRail {
  HomeRail({required this.key, required this.title, required this.movies});

  final String key;
  final String title;
  final List<Movie> movies;

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
  HomeData({required this.featured, required this.rails});

  final List<Movie> featured;
  final List<HomeRail> rails;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
        featured: ((j['featured'] ?? const []) as List)
            .map((e) => Movie.fromJson(e as Map<String, dynamic>))
            .toList(),
        rails: ((j['rails'] ?? const []) as List)
            .map((e) => HomeRail.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
