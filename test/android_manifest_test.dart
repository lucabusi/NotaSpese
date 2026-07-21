import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release APK (CI: `flutter build apk --release`) merges ONLY
/// `src/main/AndroidManifest.xml`: the INTERNET permission that ships in the
/// debug/profile manifests is a Flutter tooling artifact and is absent from
/// release. Without it every http call (frankfurter rates, Claude OCR) throws
/// SocketException, importo_eur stays NULL and all totals read 0.
void main() {
  test('main manifest declares INTERNET (release builds need it)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });
}
