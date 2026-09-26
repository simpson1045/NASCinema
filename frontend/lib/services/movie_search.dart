import '../models/movie.dart';

/// Lower-case, strip accents/punctuation, collapse spaces: "Amélie!" -> "amelie".
String normalizeForSearch(String s) {
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c',
  };
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

/// Movies matching [query], best first. Every query word must appear (as a
/// word start) in the title or the franchise name — "potter" finds all eight,
/// "jur park" finds Jurassic Park. Ranking: title starts with the query, then
/// every word matches a word start, then plain contains; popularity breaks
/// ties.
List<Movie> searchMovies(List<Movie> all, String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  final words = q.split(' ');
  final scored = <(int, double, Movie)>[];
  for (final m in all) {
    final title = normalizeForSearch(m.title);
    final hay = '$title ${normalizeForSearch(m.collectionName ?? '')}';
    final tokens = hay.split(' ');
    bool wordStart(String w) => tokens.any((t) => t.startsWith(w));
    int rank;
    if (title.startsWith(q)) {
      rank = 0;
    } else if (words.every(wordStart)) {
      rank = 1;
    } else if (hay.contains(q)) {
      rank = 2;
    } else {
      continue;
    }
    scored.add((rank, -(m.popularity ?? 0), m));
  }
  scored.sort((a, b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored) s.$3];
}
