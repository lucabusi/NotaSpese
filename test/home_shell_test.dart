import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/services/backup/backup_service.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/api_key_store.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/impostazioni/impostazioni_screen.dart';
import 'package:nota_spese/ui/shell/home_shell.dart';
import 'package:nota_spese/version.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_exchange_service.dart';

/// In-memory fake: [ApiKeyStore] wraps FlutterSecureStorage, not
/// host-testable (see class doc), so tests extend it and override the
/// three methods instead of touching the platform channel.
class _FakeApiKeyStore extends ApiKeyStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late FotoRepository fotoRepo;
  // Own (empty) dir: the settings screen measures the photo dir recursively,
  // so systemTemp itself would be walked whole.
  late Directory photoDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    photoDir = Directory.systemTemp.createTempSync('home_shell_test_');
    // No-isolate factory: see trasferta_detail_screen_test.dart.
    dbHelper = DbHelper(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    fotoRepo = FotoRepository(
      dbHelper,
      basePathProvider: () async => Directory.systemTemp.path,
    );
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
  });

  // finally: a Windows lock on the temp dir must not leak an open database
  // into the tests that follow.
  tearDown(() async {
    try {
      photoDir.deleteSync(recursive: true);
    } finally {
      await dbHelper.close();
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    ApiKeyStore? apiKeyStore,
    SettingsService? settingsService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          trasfertaRepository: trasfertaRepo,
          spesaRepository: spesaRepo,
          fotoRepository: fotoRepo,
          photoService: PhotoService(
            SettingsService(),
            basePathProvider: () async => Directory.systemTemp.path,
          ),
          captureService: ReceiptCaptureService(),
          orchestrator: RecognitionOrchestrator(
            mlkitOcr: MlkitOcrService(),
            claudeOcr: ClaudeOcrService(apiKeyProvider: () async => null),
            parser: ReceiptParser(),
            apiKeyProvider: () async => null,
          ),
          settingsService: settingsService ?? SettingsService(),
          apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
          exchangeService: FakeExchangeService(),
          cropService: CropService(
            tempDirProvider: () async => Directory.systemTemp.path,
          ),
          photoDirFor: (_) async => photoDir,
          backupService: BackupService(
            dbPathProvider: () async => p.join(Directory.systemTemp.path,
                'nota_spese_test.db'),
            photoDirProvider: () async => Directory.systemTemp,
            closeDatabase: dbHelper.close,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows three destinations and starts on Trasferte', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Nessuna trasferta'), findsOneWidget);
  });

  testWidgets('switching to Archivio shows archived list', (tester) async {
    await trasfertaRepo.insert(
      Trasferta(
        nome: 'Old',
        dataInizio: DateTime(2026, 5, 1),
        archiviata: true,
        createdAt: DateTime(2026, 5, 1),
      ),
    );
    await pump(tester);

    await tester.tap(find.text('Archivio'));
    await tester.pumpAndSettle();

    expect(find.text('Old'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsOneWidget);
  });

  testWidgets('Impostazioni tab shows the settings screen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(find.byType(ImpostazioniScreen), findsOneWidget);
    // Scroll settings ListView to render version footer (pushed down by the
    // photo and rates cards). Scope the scrollable to the settings screen: a
    // bare byType(ListView) would also match a seeded trip list, and the last
    // Scrollable is the API key TextField's own one, off-screen down here.
    await tester.dragUntilVisible(
      find.textContaining(appVersion),
      find.descendant(
        of: find.byType(ImpostazioniScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -100),
    );
    expect(find.textContaining(appVersion), findsOneWidget);
  });
}
