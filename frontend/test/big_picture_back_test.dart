import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/models/home.dart';
import 'package:nascinema/models/movie.dart';
import 'package:nascinema/screens/big_picture/big_picture_screen.dart';

Movie _movie(int id, {double? resume}) => Movie(
      id: id,
      title: 'Movie $id',
      year: 2000 + id,
      runtime: 120,
      resumePosition: resume,
    );

HomeData _home() => HomeData(
      featured: [_movie(1), _movie(2)],
      rails: [
        HomeRail(key: 'cw', title: 'Continue Watching', movies: [_movie(3, resume: 600)]),
        HomeRail(key: 'pop', title: 'Popular', movies: [_movie(4), _movie(5), _movie(6)]),
      ],
    );

void main() {
  testWidgets('Back on home opens the menu and keeps big picture open',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                BigPictureScreen(baseUrl: 'http://test', initialData: _home()),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BigPictureScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Exit Big Picture'), findsOneWidget);
    expect(find.byType(BigPictureScreen), findsOneWidget);

    // Esc again dismisses the menu and stays in big picture.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Exit Big Picture'), findsNothing);
    expect(find.byType(BigPictureScreen), findsOneWidget);

    // Tear down so the hero's timers don't outlive the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
