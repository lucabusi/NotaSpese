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

  // The other half of the BUG-02 fix (MlkitOcrService.scriptFor picking the
  // japanese recognizer): a real Maven dependency is required in Gradle
  // because the plugin ships non-latin models as compileOnly, AND its
  // matching `-dontwarn` line must be removed from proguard-rules.pro,
  // because R8 strict mode only tolerates the missing-class warning for
  // scripts that are genuinely never loaded at runtime. If the two drift
  // apart — dependency added but -dontwarn left in, or vice versa — either
  // the release build breaks (R8 failure) or the japanese recognizer is
  // silently unshipped despite MlkitOcrService requesting it.
  test('japanese ML Kit dependency and its proguard -dontwarn line stay in sync', () {
    final buildGradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final proguardRules =
        File('android/app/proguard-rules.pro').readAsStringSync();

    expect(buildGradle,
        contains('com.google.mlkit:text-recognition-japanese'));
    expect(proguardRules,
        isNot(contains('com.google.mlkit.vision.text.japanese')));
  });
}
