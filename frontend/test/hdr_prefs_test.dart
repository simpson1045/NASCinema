import 'package:flutter_test/flutter_test.dart';
import 'package:nascinema/services/hdr_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('HDR trailers default to Auto; Always/Never override detection', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await HdrPrefs.mode(), HdrMode.auto);
    // Auto off Windows (the test host) detects SDR.
    expect(await HdrPrefs.wantHdr(), isFalse);

    await HdrPrefs.setMode(HdrMode.always);
    expect(await HdrPrefs.mode(), HdrMode.always);
    expect(await HdrPrefs.wantHdr(), isTrue);

    await HdrPrefs.setMode(HdrMode.never);
    expect(await HdrPrefs.wantHdr(), isFalse);
  });
}
