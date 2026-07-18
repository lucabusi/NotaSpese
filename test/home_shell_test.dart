import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/shell/home_shell.dart';
import 'package:nota_spese/version.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late FotoRepository fotoRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // No-isolate factory: see trasferta_detail_screen_test.dart.
    dbHelper = DbHelper(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
  });

  tearDown(() => dbHelper.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(
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
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows three destinations and starts on Trasferte',
      (tester) async {
    await pump(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Nessuna trasferta'), findsOneWidget);
  });

  testWidgets('switching to Archivio shows archived list', (tester) async {
    await trasfertaRepo.insert(Trasferta(
      nome: 'Old',
      dataInizio: DateTime(2026, 5, 1),
      archiviata: true,
      createdAt: DateTime(2026, 5, 1),
    ));
    await pump(tester);

    await tester.tap(find.text('Archivio'));
    await tester.pumpAndSettle();

    expect(find.text('Old'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsOneWidget);
  });

  testWidgets('Impostazioni tab shows placeholder with version',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(find.textContaining(appVersion), findsOneWidget);
  });
}
