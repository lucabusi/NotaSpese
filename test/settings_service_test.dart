import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults: quality 70, internal photo dir', () async {
    final s = SettingsService();
    expect(await s.jpgQuality, 70);
    expect(await s.photoDirKind, PhotoDirKind.internal);
  });

  test('set + get persist', () async {
    final s = SettingsService();
    await s.setJpgQuality(85);
    await s.setPhotoDirKind(PhotoDirKind.external);
    expect(await s.jpgQuality, 85);
    expect(await s.photoDirKind, PhotoDirKind.external);
  });

  test('quality clamped to 50-90', () async {
    final s = SettingsService();
    await s.setJpgQuality(10);
    expect(await s.jpgQuality, 50);
    await s.setJpgQuality(100);
    expect(await s.jpgQuality, 90);
  });

  test('unknown stored dir kind falls back to internal', () async {
    SharedPreferences.setMockInitialValues({'photo_dir': 'bogus'});
    final s = SettingsService();
    expect(await s.photoDirKind, PhotoDirKind.internal);
  });

  group('ocrEngineDefault', () {
    test('default: mlkit when unset', () async {
      final s = SettingsService();
      expect(await s.ocrEngineDefault, OcrEngine.mlkit);
    });

    test('set claude then get returns claude, persisted as "claude"', () async {
      final s = SettingsService();
      await s.setOcrEngineDefault(OcrEngine.claude);
      expect(await s.ocrEngineDefault, OcrEngine.claude);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ocr_engine'), 'claude');
    });

    test('corrupt stored value falls back to mlkit', () async {
      SharedPreferences.setMockInitialValues({'ocr_engine': 'local_ai'});
      final s = SettingsService();
      expect(await s.ocrEngineDefault, OcrEngine.mlkit);
    });
  });
}
