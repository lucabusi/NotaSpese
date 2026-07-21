import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
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

import 'fakes/fake_exchange_service.dart';

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
        exchangeService: FakeExchangeService(),
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

  testWidgets('overall total warns about spese without conversion',
      (tester) async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 16, 20),
    ));

    await pump(tester);

    expect(find.text('Totale complessivo'), findsOneWidget);
    expect(find.text('esclude 1 spese senza conversione'), findsOneWidget);
  });

  Finder totalHeaderCard() => find.ancestor(
      of: find.text('Totale complessivo'), matching: find.byType(Card));

  testWidgets(
      'overall total shows a dash instead of € 0,00 when zero and there '
      'are unconverted spese', (tester) async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 16, 20),
    ));

    await pump(tester);

    final header = totalHeaderCard();
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('—')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('€ 0,00')),
        findsNothing);
  });

  testWidgets(
      'overall total shows € 0,00 when genuinely empty (no unconverted '
      'spese)', (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));

    await pump(tester);

    final header = totalHeaderCard();
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('€ 0,00')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('—')),
        findsNothing);
  });
}
