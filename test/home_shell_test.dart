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
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/api_key_store.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/shell/home_shell.dart';
import 'package:nota_spese/version.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_exchange_service.dart';

/// In-memory fake: [ApiKeyStore] wraps FlutterSecureStorage, not
/// host-testable (see class doc), so tests extend it and override the
/// three methods instead of touching the platform channel.
class _FakeApiKeyStore extends ApiKeyStore {
  _FakeApiKeyStore([this._value]);

  String? _value;
  String? written;
  bool deleted = false;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    written = value;
    _value = value;
  }

  @override
  Future<void> delete() async {
    deleted = true;
    _value = null;
  }
}

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

  Future<void> pump(
    WidgetTester tester, {
    ApiKeyStore? apiKeyStore,
    SettingsService? settingsService,
  }) async {
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
        settingsService: settingsService ?? SettingsService(),
        apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
        exchangeService: FakeExchangeService(),
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

    // Scroll settings ListView to render version footer (pushed down by rates toggle card).
    await tester.dragUntilVisible(
      find.textContaining(appVersion),
      find.byType(Scrollable).last,
      const Offset(0, -100),
    );
    expect(find.textContaining(appVersion), findsOneWidget);
  });

  group('Impostazioni — Claude API key', () {
    testWidgets('initial state is non configurata, no Rimuovi button',
        (tester) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.text('Configurata'), findsNothing);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
    });

    testWidgets(
        'saving calls write with the typed value, shows configurata, clears field',
        (tester) async {
      final store = _FakeApiKeyStore();
      await pump(tester, apiKeyStore: store);

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('campo-api-key')), 'sk-segreta-123');
      await tester.tap(find.byKey(const Key('salva-api-key')));
      await tester.pumpAndSettle();

      expect(store.written, 'sk-segreta-123');
      expect(find.text('Configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsOneWidget);

      final field =
          tester.widget<TextField>(find.byKey(const Key('campo-api-key')));
      expect(field.controller!.text, isEmpty);

      // The raw key must never appear rendered anywhere in the tree.
      expect(find.textContaining('sk-segreta-123'), findsNothing);
    });

    testWidgets('removing calls delete and reverts to non configurata',
        (tester) async {
      final store = _FakeApiKeyStore('sk-esistente');
      await pump(tester, apiKeyStore: store);

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Configurata'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rimuovi-api-key')));
      await tester.pumpAndSettle();

      expect(store.deleted, isTrue);
      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
    });
  });

  group('Impostazioni — motore OCR predefinito', () {
    testWidgets('Claude segment disabled when key not configured',
        (tester) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      final button = tester.widget<SegmentedButton<OcrEngine>>(
          find.byKey(const Key('motore-default')));
      final claude =
          button.segments.firstWhere((s) => s.value == OcrEngine.claude);
      expect(claude.enabled, isFalse);
    });

    testWidgets('selecting Claude persists the default via SettingsService',
        (tester) async {
      final settingsService = SettingsService();
      await pump(tester,
          apiKeyStore: _FakeApiKeyStore('sk-esistente'),
          settingsService: settingsService);

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byKey(const Key('motore-default')),
          matching: find.text('Claude')));
      await tester.pumpAndSettle();

      expect(await settingsService.ocrEngineDefault, OcrEngine.claude);
      final button = tester.widget<SegmentedButton<OcrEngine>>(
          find.byKey(const Key('motore-default')));
      expect(button.selected, {OcrEngine.claude});
    });

    testWidgets(
        'removing the key while default is claude reverts default to mlkit',
        (tester) async {
      final settingsService = SettingsService();
      await settingsService.setOcrEngineDefault(OcrEngine.claude);
      final store = _FakeApiKeyStore('sk-esistente');
      await pump(tester, apiKeyStore: store, settingsService: settingsService);

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      final before = tester.widget<SegmentedButton<OcrEngine>>(
          find.byKey(const Key('motore-default')));
      expect(before.selected, {OcrEngine.claude});

      await tester.tap(find.byKey(const Key('rimuovi-api-key')));
      await tester.pumpAndSettle();

      expect(await settingsService.ocrEngineDefault, OcrEngine.mlkit);
      final after = tester.widget<SegmentedButton<OcrEngine>>(
          find.byKey(const Key('motore-default')));
      expect(after.selected, {OcrEngine.mlkit});
    });
  });

  testWidgets('toggle tassi online: default ON, tap persiste OFF',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('toggle-tassi-online'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await SettingsService().tassiOnline, isFalse);
  });
}
