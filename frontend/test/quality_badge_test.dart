import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/models/movie.dart';

String? badge(String res, {bool hdr = false}) =>
    Movie(id: 1, title: 't', resolution: res, hdr: hdr).qualityBadge;

void main() {
  test('cropped scope films are judged by their 16:9-equivalent height', () {
    expect(badge('1920x816'), '1080p'); // Mr. & Mrs. Smith — showed "720p"
    expect(badge('1920x800'), '1080p');
    expect(badge('1918x812'), '1080p'); // Die Hard
    expect(badge('3840x1600', hdr: true), '4K HDR'); // showed "1080p HDR"
    expect(badge('3824x1588'), '4K'); // Expend4bles
  });

  test('4:3 and plain 16:9 still read right', () {
    expect(badge('2880x2160'), '4K'); // A Charlie Brown Christmas
    expect(badge('1440x1072'), '1080p'); // Frosty the Snowman
    expect(badge('1920x1080'), '1080p');
    expect(badge('3840x2160'), '4K');
    expect(badge('1280x720'), '720p');
    expect(badge('720x480'), 'SD');
  });
}
