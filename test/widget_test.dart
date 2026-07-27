// Smoke test: the app builds with the home shell.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/app.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/api_key_store.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_exchange_service.dart';

/// In-memory fake: [ApiKeyStore] wraps FlutterSecureStorage, not
/// host-testable (see class doc). IndexedStack builds all shell tabs
/// eagerly, so the Impostazioni tab's initState always runs.
class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('App builds and shows the shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // No-isolate factory: see trasferta_detail_screen_test.dart.
    final dbHelper = DbHelper(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    final trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    final spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    addTearDown(dbHelper.close);
    // Own (empty) dir: the settings tab measures the photo dir recursively,
    // so systemTemp itself would be walked whole.
    final photoDir = Directory.systemTemp.createTempSync('widget_test_');
    addTearDown(() => photoDir.deleteSync(recursive: true));

    await tester.pumpWidget(NotaSpeseApp(
      trasfertaRepository: trasfertaRepo,
      spesaRepository: spesaRepo,
      fotoRepository: fotoRepo,
      photoService: PhotoService(SettingsService(),
          basePathProvider: () async => Directory.systemTemp.path),
      captureService: ReceiptCaptureService(),
      orchestrator: RecognitionOrchestrator(
        mlkitOcr: MlkitOcrService(),
        claudeOcr: ClaudeOcrService(apiKeyProvider: () async => null),
        parser: ReceiptParser(),
        apiKeyProvider: () async => null,
      ),
      settingsService: SettingsService(),
      apiKeyStore: _FakeApiKeyStore(),
      exchangeService: FakeExchangeService(),
      cropService: CropService(
          tempDirProvider: () async => Directory.systemTemp.path),
      photoDirFor: (_) async => photoDir,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
  });
}
