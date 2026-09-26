import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/models/movie.dart';
import 'package:nascinema/screens/big_picture/bp_search_screen.dart';
import 'package:nascinema/services/movie_search.dart';

Movie _m(int id, String t, {String? col, double pop = 1, int? year}) =>
    Movie(id: id, title: t, collectionName: col, popularity: pop, year: year);

final _lib = [
  _m(1, "Harry Potter and the Sorcerer's Stone", col: 'Harry Potter Collection', pop: 90),
  _m(2, 'Harry Potter and the Chamber of Secrets', col: 'Harry Potter Collection', pop: 80),
  _m(3, 'Jurassic Park', col: 'Jurassic Park Collection', pop: 70),
  _m(4, 'The Lost World: Jurassic Park', col: 'Jurassic Park Collection', pop: 50),
  _m(5, 'Amélie', pop: 40),
  _m(6, 'Rocky', col: 'Rocky Collection', pop: 60),
  _m(7, 'Rocky IV', col: 'Rocky Collection', pop: 65),
  _m(8, "Schindler's List", pop: 30),
];

void main() {
  List<String> titles(String q) => [for (final m in searchMovies(_lib, q)) m.title];

  test('series names, word starts, accents and punctuation', () {
    expect(titles('potter'), hasLength(2));
    expect(titles('jur park'), ['Jurassic Park', 'The Lost World: Jurassic Park']);
    expect(titles('amelie'), ['Amélie']);
    expect(titles('schindlers'), ["Schindler's List"]);
    expect(titles(''), isEmpty);
    expect(titles('zzz'), isEmpty);
  });

  test('title-starts-with beats elsewhere; popularity breaks ties', () {
    // "rocky" starts both titles -> by popularity (IV is more popular).
    expect(titles('rocky'), ['Rocky IV', 'Rocky']);
    // "jurassic": Jurassic Park starts with it; Lost World only contains it.
    expect(titles('jurassic').first, 'Jurassic Park');
  });

  testWidgets('typing on a real keyboard fills results', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pumpWidget(MaterialApp(
        home: BpSearchScreen(baseUrl: 'http://nas', initialLibrary: _lib)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Start typing'), findsOneWidget);
    for (final k in [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyO,
        LogicalKeyboardKey.keyT]) {
      await tester.sendKeyEvent(k);
      await tester.pump();
    }
    expect(find.text('2 results'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(find.textContaining('Start typing'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
