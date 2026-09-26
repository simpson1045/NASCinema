import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nascinema/services/flag_service.dart';
import 'package:nascinema/widgets/flag_host.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('F8 sends the top screen, its movie + position, and a screenshot',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'NASCinema', packageName: 'nascinema', version: '0.5.9',
        buildNumber: '25', buildSignature: '');
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      expect(req.url.toString(), 'http://nas:8400/api/flags');
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });

    FlagService.newClient = () => client;
    {
      await tester.pumpWidget(MaterialApp(
        builder: (_, child) => FlagHost(child: child!),
        home: const Scaffold(body: Center(child: Text('Jurassic Park'))),
      ));
      final home = Object(), trailer = Object();
      FlagService.register(home, 'bp-home', 'http://nas:8400');
      FlagService.register(trailer, 'bp-trailer', 'http://nas:8400', () => {
            'kind': 'trailer',
            'movie_id': 123,
            'movie_title': 'Jurassic Park',
            'position_seconds': 42.5,
            'trailer_url': '/api/movies/123/trailer',
          });

      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pump();
      expect(find.text('Flagged ✓'), findsOneWidget);
      // The flag's awaits (version, screenshot, upload) need real async
      // turns and frames — alternate the two until the upload lands.
      for (var i = 0; i < 100 && sent.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(FlagService.toast.value, 'Flagged ✓'); // not a failure message

      expect(sent, hasLength(1));
      final f = sent.single;
      expect(f['screen'], 'bp-trailer');
      expect(f['kind'], 'trailer');
      expect(f['movie_id'], 123);
      expect(f['position_seconds'], 42.5);
      expect(f['app_version'], '0.5.9+25');
      expect(f['context']['trailer_url'], '/api/movies/123/trailer');
      expect(f['context']['screens'], ['bp-home', 'bp-trailer']);
      expect((f['screenshot_png_b64'] as String?)?.isNotEmpty, isTrue);

      // Leaving the trailer makes home the top screen again.
      FlagService.unregister(trailer);
      FlagService.unregister(home);
      await tester.pump(const Duration(seconds: 3)); // toast timer
    }
  });
}
