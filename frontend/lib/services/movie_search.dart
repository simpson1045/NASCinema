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
  final scored = [
    for (final (rank, m) in rankTitles(all, query, (m) => m.title, (m) => m.collectionName))
      (rank, -(m.popularity ?? 0), m),
  ];
  scored.sort((a, b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored) s.$3];
}

/// Every item matching [query] with its rank — 0: the title starts with the
/// query, 1: every query word starts a word of the title (or [extra], e.g. the
/// franchise), 2: plain contains. Movies and TV shows rank the same way.
List<(int, T)> rankTitles<T>(Iterable<T> all, String query,
    String Function(T) title, [String? Function(T)? extra]) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  final words = q.split(' ');
  final out = <(int, T)>[];
  for (final item in all) {
    final t = normalizeForSearch(title(item));
    final hay = '$t ${normalizeForSearch(extra?.call(item) ?? '')}';
    final tokens = hay.split(' ');
    bool wordStart(String w) => tokens.any((tok) => tok.startsWith(w));
    if (t.startsWith(q)) {
      out.add((0, item));
    } else if (words.every(wordStart)) {
      out.add((1, item));
    } else if (hay.contains(q)) {
      out.add((2, item));
    }
  }
  return out;
}
