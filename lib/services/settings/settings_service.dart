import 'package:shared_preferences/shared_preferences.dart';

import '../ocr/parsed_receipt.dart';

/// Photo directory choice, limited to app-specific dirs in v1.0
/// (scoped storage constraint, Specifiche.md §2). SAF → v1.1.
enum PhotoDirKind { internal, external }

/// Minimal settings (born in fase 4, ToDo): JPG quality + photo directory
/// on SharedPreferences. The full settings screen arrives in fase 8 and
/// extends this service.
class SettingsService {
  static const String _kJpgQuality = 'jpg_quality';
  static const String _kPhotoDir = 'photo_dir';
  static const String _kOcrEngine = 'ocr_engine';
  static const String _kTassiOnline = 'tassi_online';

  static const int defaultJpgQuality = 70;
  static const int minJpgQuality = 50;
  static const int maxJpgQuality = 90;

  Future<int> get jpgQuality async =>
      (await SharedPreferences.getInstance()).getInt(_kJpgQuality) ??
      defaultJpgQuality;

  Future<void> setJpgQuality(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kJpgQuality, value.clamp(minJpgQuality, maxJpgQuality));
  }

  Future<PhotoDirKind> get photoDirKind async {
    final stored =
        (await SharedPreferences.getInstance()).getString(_kPhotoDir);
    return PhotoDirKind.values.asNameMap()[stored] ?? PhotoDirKind.internal;
  }

  Future<void> setPhotoDirKind(PhotoDirKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhotoDir, kind.name);
  }

  Future<OcrEngine> get ocrEngineDefault async {
    final stored =
        (await SharedPreferences.getInstance()).getString(_kOcrEngine);
    return OcrEngine.values.asNameMap()[stored] ?? OcrEngine.mlkit;
  }

  Future<void> setOcrEngineDefault(OcrEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOcrEngine, engine.name);
  }

  /// Fase 6: master switch for frankfurter.app calls (Settings toggle).
  Future<bool> get tassiOnline async =>
      (await SharedPreferences.getInstance()).getBool(_kTassiOnline) ?? true;

  Future<void> setTassiOnline(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTassiOnline, value);
  }
}
