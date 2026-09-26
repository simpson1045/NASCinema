import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/models/movie_file.dart';
import 'package:nascinema/screens/big_picture/bp_track_picker.dart';

MovieFile _f(int id, String label, List<MediaTrack> audio) => MovieFile(
    id: id, label: label, quality: label, audioTracks: audio,
    subtitleTracks: const [
      MediaTrack(id: 1, title: 'English', desc: 'English · PGS', language: 'eng'),
    ]);

void main() {
  final files = [
    _f(1007, '4K · HDR · TrueHD 7.1', const [
      MediaTrack(id: 1, title: 'Surround 7.1', language: 'eng', isDefault: true, lossless: true),
    ]),
    _f(1008, '4K77', const [
      MediaTrack(id: 1, title: '2.0 DTS-HD-MA (1977 35mm stereo mix 2018)', language: 'eng', isDefault: true),
      MediaTrack(id: 2, title: '5.1 DTS-HD-MA (1977 70mm six track mix 2018)', language: 'eng'),
      MediaTrack(id: 3, title: '1.0 DTS-HD-MA (1977 35mm mono mix)', language: 'eng', lossless: true),
    ]),
  ];

  testWidgets('pick 4K77 + the 1977 mono mix + subtitles off', (tester) async {
    TrackPick? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(ctx).push<TrackPick>(MaterialPageRoute(
                builder: (_) => BpTrackPicker(
                  title: 'Star Wars',
                  files: files,
                  initial: TrackPick(fileId: 1007, audio: 1),
                  baseUrl: 'http://nas',
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> key(LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pump();
    }

    await key(LogicalKeyboardKey.arrowDown); // version: 4K77
    await key(LogicalKeyboardKey.enter); // -> audio column
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.arrowDown); // the mono mix
    expect(find.text('LOSSLESS'), findsWidgets);
    await key(LogicalKeyboardKey.enter); // -> subtitles column
    // No forced/default subtitle in this file, so there's no "Automatic" —
    // the cursor already sits on "Off".
    expect(find.text('Automatic'), findsNothing);
    await key(LogicalKeyboardKey.enter); // choose + close
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.fileId, 1008);
    expect(result!.audio, 3);
    expect(result!.subtitle, 0);
    expect(result!.summary(files),
        '4K77  ·  1.0 DTS-HD-MA (1977 35mm mono mix)  ·  Subtitles off');
  });

  test('changing audio keeps a downloaded subtitle; summary names it', () {
    const p = TrackPick(fileId: 1008, audio: 1, subtitle: 0, external: 'en-123');
    final q = p.copyWith(audio: 3);
    expect(q.external, 'en-123');
    expect(q.audio, 3);
    expect(q.copyWith(clearExternal: true).external, isNull);
    expect(q.summary(files), contains('Subtitles: downloaded (EN)'));
  });
}
