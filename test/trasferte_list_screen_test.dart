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
import 'package:nota_spese/ui/shared/widgets/trip_card.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_screen.dart';
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

  Future<void> pump(WidgetTester tester, {bool archiviate = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasferteListScreen(
        controller: TrasferteListController(trasfertaRepo, spesaRepo,
            archiviate: archiviate),
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

  Trasferta trasferta({String nome = 'Trip', bool archiviata = false}) =>
      Trasferta(
        nome: nome,
        dataInizio: DateTime(2026, 7, 15),
        archiviata: archiviata,
        createdAt: DateTime(2026, 7, 15, 8),
      );

  testWidgets('shows empty state with CTA on active tab', (tester) async {
    await pump(tester);
    expect(find.text('Nessuna trasferta'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('lists active trips with total header', (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await pump(tester);

    expect(find.byType(TripCard), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Totale complessivo'), findsOneWidget);
  });

  testWidgets('create flow: FAB → form → save → list updated',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo-nome')), 'Milano');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Milano'), findsOneWidget);
    expect(await trasfertaRepo.getAttive(), hasLength(1));
  });

  testWidgets('archive tab: no FAB, no header, shows archived',
      (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    await pump(tester, archiviate: true);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Totale complessivo'), findsNothing);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsOneWidget);
  });

  testWidgets('card menu elimina asks confirmation then deletes',
      (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await pump(tester);

    await tester.tap(find.byType(PopupMenuButton<TripCardAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina').last); // confirm dialog
    await tester.pumpAndSettle();

    expect(find.byType(TripCard), findsNothing);
    expect(await trasfertaRepo.getAttive(), isEmpty);
  });
}
