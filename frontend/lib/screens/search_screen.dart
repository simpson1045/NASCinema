import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_screen.dart';

/// Type-ahead search over the whole library. The catalog is small enough
/// (hundreds of titles) that we fetch it once and filter client-side —
/// results update on every keystroke with zero server round-trips.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Movie>? _all; // null = still loading
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    ApiService(widget.baseUrl).listMovies().then((movies) {
      if (mounted) setState(() => _all = movies);
    }).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Title-prefix matches first (typing "rev" puts Revenge of the Sith above
  /// titles that merely contain "rev"), then word-prefix, then substring.
  /// A 4-digit query also matches the year.
  List<Movie> _results() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty || _all == null) return const [];
    final starts = <Movie>[];
    final wordStarts = <Movie>[];
    final contains = <Movie>[];
    for (final m in _all!) {
      final t = m.title.toLowerCase();
      if (t.startsWith(q)) {
        starts.add(m);
      } else if (t.split(RegExp(r'[^a-z0-9]+')).any((w) => w.startsWith(q))) {
        wordStarts.add(m);
      } else if (t.contains(q) || (m.year != null && '${m.year}' == q)) {
        contains.add(m);
      }
    }
    return [...starts, ...wordStarts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    final results = _results();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: NasColors.text, fontSize: 16),
          cursorColor: NasColors.amber,
          decoration: InputDecoration(
            hintText: 'Search movies…',
            hintStyle: const TextStyle(color: NasColors.muted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear,
                        color: NasColors.muted, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: _error != null
          ? Center(
              child: Text('Search unavailable:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NasColors.bad)))
          : _all == null
              ? const Center(
                  child: CircularProgressIndicator(color: NasColors.amber))
              : _query.trim().isEmpty
                  ? Center(
                      child: Text('Search ${_all!.length} movies',
                          style: const TextStyle(
                              color: NasColors.muted, fontSize: 14)))
                  : results.isEmpty
                      ? const Center(
                          child: Text('No matches',
                              style: TextStyle(
                                  color: NasColors.muted, fontSize: 14)))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 12,
                            // poster 2:3 plus two text lines
                            childAspectRatio: 0.58,
                          ),
                          itemCount: results.length,
                          itemBuilder: (_, i) =>
                              _ResultTile(results[i], widget.baseUrl),
                        ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.movie, this.baseUrl);

  final Movie movie;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final url = movie.posterUrl();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MovieDetailScreen(movie: movie, baseUrl: baseUrl),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.expand(
                child: url == null
                    ? const ColoredBox(
                        color: NasColors.surfaceRaised,
                        child: Icon(Icons.movie_outlined,
                            color: NasColors.muted, size: 26))
                    : Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                            color: NasColors.surfaceRaised,
                            child: Icon(Icons.movie_outlined,
                                color: NasColors.muted, size: 26))),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: NasColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
          Text(
            [
              if (movie.year != null) '${movie.year}',
              if (movie.imdbRating != null)
                '★ ${movie.imdbRating!.toStringAsFixed(1)}',
            ].join('  ·  '),
            style: const TextStyle(color: NasColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
