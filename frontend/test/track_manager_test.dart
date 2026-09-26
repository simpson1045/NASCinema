import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/screens/big_picture/bp_track_manager.dart';

void main() {
  test('fmtBytes', () {
    expect(fmtBytes(70100000000), '70.1 GB');
    expect(fmtBytes(5500000000), '5.5 GB');
    expect(fmtBytes(850000000), '850 MB');
    expect(fmtBytes(27000000), '27 MB');
    expect(fmtBytes(0), '0 B');
  });
}
