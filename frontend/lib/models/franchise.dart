import 'movie.dart';

/// A franchise (TMDB collection) with 2+ movies in the library: its own art
/// (logo, backdrop) plus its movies' backdrops for the animated home tile.
class Franchise {
  Franchise({
    required this.id,
    required this.name,
    required this.count,
    this.years,
    this.logo,
    this.backdrop,
    this.overview,
    this.backdropPaths = const [],
    this.movies = const [],
  });

  final int id;
  final String name; // "Harry Potter" (no "Collection")
  final int count;
  final String? years; // "2001–2011"
  final String? logo;
  final String? backdrop; // full URL (TMDB original)
  final String? overview;
  final List<String> backdropPaths; // members' TMDB backdrop paths, in order
  final List<Movie> movies; // only on the franchise page

  List<String> backdropUrls({String size = 'w780'}) => [
        for (final p in backdropPaths) 'https://image.tmdb.org/t/p/$size$p',
      ];

  factory Franchise.fromJson(Map<String, dynamic> j) => Franchise(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        years: j['years'] as String?,
        logo: j['logo'] as String?,
        backdrop: j['backdrop'] as String?,
        overview: j['overview'] as String?,
        backdropPaths: [
          for (final p in (j['backdrops'] as List? ?? const [])) p.toString(),
        ],
        movies: [
          for (final m in (j['movies'] as List? ?? const []))
            Movie.fromJson(m as Map<String, dynamic>),
        ],
      );
}
