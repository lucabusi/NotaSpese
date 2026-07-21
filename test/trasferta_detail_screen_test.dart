import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_exchange_service.dart';

/// Fake capture: the scanner "returns" a prepared local jpg.
class _FakeCaptureService extends ReceiptCaptureService {
  _FakeCaptureService(this.path);

  final String path;

  @override
  Future<String?> scanWithDocumentScanner() async => path;
}

/// Fake orchestrator: default `recognize` resolves immediately with a
/// pre-filled receipt (engine == the one requested); override
/// [recognizeImpl] per test for fallback/empty/never-completing scenarios.
class _FakeOrchestrator extends RecognitionOrchestrator {
  _FakeOrchestrator({this.claudeAvailableValue = true})
      : super(
          mlkitOcr: MlkitOcrService(),
          claudeOcr: ClaudeOcrService(apiKeyProvider: () async => null),
          parser: ReceiptParser(),
          apiKeyProvider: () async => null,
        );

  bool claudeAvailableValue;
  Future<RecognitionResult> Function(String imagePath, OcrEngine engine)?
      recognizeImpl;
  final List<OcrEngine> calls = [];
  final List<String?> linguaHints = [];

  /// Which path each `recognize` call actually received: the seam finding
  /// 5 covers — nothing previously asserted on this, so a build that fed
  /// the raw capture straight to OCR (ignoring the crop) would have passed
  /// the whole suite.
  final List<String> imagePaths = [];

  @override
  Future<bool> get claudeAvailable async => claudeAvailableValue;

  @override
  Future<RecognitionResult> recognize(
    String imagePath, {
    required OcrEngine engine,
    String? linguaHint,
  }) {
    calls.add(engine);
    imagePaths.add(imagePath);
    linguaHints.add(linguaHint);
    return recognizeImpl?.call(imagePath, engine) ??
        Future.value(RecognitionResult(
          receipt: ParsedReceipt(
            importo: 12.5,
            fornitore: 'Bar Roma',
            data: DateTime(2026, 7, 10),
            engine: engine,
          ),
          claudeFallbackToMlkit: false,
        ));
  }
}

/// Fake crop: always returns [output] regardless of the rect, so a test
/// can prove OCR and the saved photo derive from what CropService
/// produced, not from the raw capture.
class _FakeCropService extends CropService {
  _FakeCropService(this.output)
      : super(tempDirProvider: () async => Directory.systemTemp.path);

  final String output;

  @override
  Future<String> crop(String sourcePath, CropRect rect) async => output;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late FotoRepository fotoRepo;
  late PhotoService photoService;
  late Directory baseDir;
  late Directory cropDir;
  late String sourceJpg;
  late int trasfertaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Real IO must happen here: setUp runs outside FakeAsync (see gotcha
    // in spesa_form_screen_test.dart).
    baseDir = await Directory.systemTemp.createTemp('detail_screen');
    cropDir = await Directory.systemTemp.createTemp('detail_screen_crop');
    final im = img.Image(width: 320, height: 240);
    img.fill(im, color: img.ColorRgb8(120, 40, 200));
    sourceJpg = p.join(baseDir.path, 'src.jpg');
    await File(sourceJpg).writeAsBytes(img.encodeJpg(im));

    // No-isolate factory: futures complete as microtasks, so widget tests
    // (FakeAsync) don't hang waiting on a real isolate response.
    dbHelper = DbHelper(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    fotoRepo =
        FotoRepository(dbHelper, basePathProvider: () async => baseDir.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    photoService = PhotoService(SettingsService(),
        basePathProvider: () async => baseDir.path);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() async {
    await dbHelper.close();
    try {
      await baseDir.delete(recursive: true);
    } on FileSystemException {
      // Windows: Image.file may still hold a handle on a temp jpg.
    }
    try {
      await cropDir.delete(recursive: true);
    } on FileSystemException {
      // Windows: Image.file may still hold a handle on a temp jpg.
    }
  });

  Future<void> pump(WidgetTester tester,
      {_FakeOrchestrator? orchestrator,
      int? id,
      CropService? cropService}) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasfertaDetailScreen(
        controller: TrasfertaDetailController(
            id ?? trasfertaId, trasfertaRepo, spesaRepo, fotoRepo, photoService),
        captureService: _FakeCaptureService(sourceJpg),
        orchestrator: orchestrator ?? _FakeOrchestrator(),
        settingsService: SettingsService(),
        exchangeService: FakeExchangeService(),
        cropService: cropService ??
            CropService(tempDirProvider: () async => cropDir.path),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // Lets real file IO (PhotoService, file deletes) complete: each awaited
  // real-IO step resumes as ONE FakeAsync microtask, so alternate "run the
  // real event loop" (runAsync) and "flush microtasks/frames" (pump) once
  // per step in the pipeline, then settle the UI.
  Future<void> settleWithRealIo(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // Pumps one frame at a time until [finder] matches, then stops — instead
  // of a fixed pump count, which would either undershoot (miss the crop
  // confirm's own blocking-progress dialog, interposed since the crop
  // temp-file fix) or overshoot past a transient state, e.g. the OCR
  // progress dialog when the (fake) orchestrator resolves immediately.
  // pumpAndSettle can't be used here: a still-pending future behind a
  // CircularProgressIndicator reschedules frames forever.
  Future<void> pumpUntilVisible(WidgetTester tester, Finder finder,
      {int maxPumps = 20}) async {
    for (var i = 0; i < maxPumps; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump();
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no spese', (tester) async {
    await pump(tester);

    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Nessuna spesa registrata'), findsOneWidget);
    expect(find.text('€ 0,00'), findsOneWidget);
  });

  testWidgets('header shows the original currency first, EUR as a hint',
      (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      importoEur: 17.9,
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    // Amount appears three times: trip total in the header, the (only)
    // category bar, and the spesa tile — all 3000, all now rendered with
    // formatValuta so the decimal count matches JPY (0 decimals) too.
    expect(find.text('¥ 3.000'), findsNWidgets(3));
    expect(find.text('≈ € 17,90'), findsOneWidget);
    expect(find.text('Totali per categoria (JPY)'), findsOneWidget);
  });

  testWidgets('no EUR conversion: no euro line at all, never € 0,00',
      (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    // Amount appears three times: trip total in the header, the (only)
    // category bar, and the spesa tile.
    expect(find.text('¥ 3.000'), findsNWidgets(3));
    expect(find.textContaining('≈ €'), findsNothing);
    expect(find.text('€ 0,00'), findsNothing);
    expect(find.text('1 spese senza conversione EUR'), findsOneWidget);
  });

  testWidgets(
      'category card notes spese senza conversione when it falls back to '
      'EUR with mixed currencies', (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 45320,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 20),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 12),
      categoria: Categoria.taxi,
      importo: 20,
      valuta: 'EUR',
      importoEur: 20,
      createdAt: DateTime(2026, 7, 12, 9),
    ));

    await pump(tester);

    final categoryCard = find.ancestor(
        of: find.text('Totali per categoria (EUR)'),
        matching: find.byType(Card));
    expect(categoryCard, findsOneWidget);
    expect(
        find.descendant(
            of: categoryCard,
            matching: find.text('1 spese senza conversione EUR')),
        findsOneWidget);
  });

  testWidgets('category card has no senza-conversione note on a '
      'single-currency trip', (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 12,
      valuta: 'EUR',
      importoEur: 12,
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    expect(find.text('Totali per categoria (EUR)'), findsOneWidget);
    expect(find.textContaining('spese senza conversione EUR'), findsNothing);
  });

  testWidgets('single EUR currency: no redundant ≈ € line', (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 12,
      valuta: 'EUR',
      importoEur: 12,
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    expect(find.textContaining('≈ €'), findsNothing);
  });

  testWidgets(
      'header rows: trip currency first, others by descending amount',
      (tester) async {
    // Trip currency (EUR, from the fixture) gets the smallest amount, so
    // the assertion actually pins the "trip currency first" rule rather
    // than passing by coincidence of a plain amount sort.
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 5,
      valuta: 'EUR',
      importoEur: 5,
      createdAt: DateTime(2026, 7, 11, 21),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 12),
      categoria: Categoria.trasporto,
      importo: 50,
      valuta: 'USD',
      importoEur: 46,
      createdAt: DateTime(2026, 7, 12, 9),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 13),
      categoria: Categoria.altro,
      importo: 20,
      valuta: 'GBP',
      importoEur: 23,
      createdAt: DateTime(2026, 7, 13, 9),
    ));

    await pump(tester);

    // Isolate the totals header Card (identified via its fixed label) so
    // the per-currency row lookup can't match the per-spesa list tiles
    // rendered further down in the same amounts.
    final headerCard = find.ancestor(
        of: find.text('Totale trasferta'), matching: find.byType(Card));
    expect(headerCard, findsOneWidget);

    double dyOf(String text) => tester
        .getTopLeft(find.descendant(
            of: headerCard, matching: find.text(text)))
        .dy;

    final eurY = dyOf('€ 5,00');
    final usdY = dyOf('\$ 50,00');
    final gbpY = dyOf('£ 20,00');

    expect(eurY, lessThan(usdY));
    expect(usdY, lessThan(gbpY));
  });

  testWidgets('lists spese grouped by date', (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      fornitore: 'Ichiran',
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    expect(find.text('11/07/2026'), findsOneWidget);
    // "Cena" appears twice: category bar label + spesa tile subtitle.
    expect(find.text('Cena'), findsNWidgets(2));
    // '¥ 3.000' appears three times: header total, category bar, spesa
    // tile — all now rendered via formatValuta with JPY's 0 decimals.
    expect(find.text('¥ 3.000'), findsNWidgets(3));
    expect(find.text('Nessuna spesa registrata'), findsNothing);
  });

  testWidgets('FAB opens add sheet: scatta and manuale both enabled',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final scatta =
        tester.widget<ListTile>(find.byKey(const Key('sheet-scatta')));
    expect(scatta.enabled, isTrue);

    await tester.tap(find.byKey(const Key('sheet-manuale')));
    await tester.pumpAndSettle();
    expect(find.text('Nuova spesa'), findsOneWidget);
  });

  testWidgets('manual expense flow: create, totals, edit, delete',
      (tester) async {
    await pump(tester);

    // Crea: 12 EUR, categoria Cena.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-manuale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-1')));
    await tester.tap(find.byKey(const Key('key-2')));
    await scrollTo(tester, find.byKey(const Key('chip-cena')));
    await tester.tap(find.byKey(const Key('chip-cena')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    // Lista + totali aggiornati (header, tile, barra categoria).
    expect(find.text('€ 12,00'), findsWidgets);
    expect(find.text('Totali per categoria (EUR)'), findsOneWidget);
    expect(find.text('Cena'), findsWidgets);

    // Modifica: 12 → 125.
    await tester.tap(find.widgetWithText(ListTile, 'Cena').first);
    await tester.pumpAndSettle();
    expect(find.text('Modifica spesa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-5')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(find.text('€ 125,00'), findsWidgets);

    // Elimina con conferma.
    await tester.tap(find.widgetWithText(ListTile, 'Cena').first);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('elimina-spesa')));
    await tester.tap(find.byKey(const Key('elimina-spesa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna spesa registrata'), findsOneWidget);
    expect(find.text('Totali per categoria (EUR)'), findsNothing);
  });

  testWidgets(
      'photo flow: scatta → form preview → save → thumb in list → '
      'delete spesa removes files', (tester) async {
    await pump(tester);

    // 📷 Scatta: fake scanner ritorna il jpg preparato → crop → form con
    // preview.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();
    expect(find.text('Nuova spesa'), findsOneWidget);

    // Importo digitato PRIMA dello scroll (la ListView lazy smonta il
    // keypad in alto quando si scorre in fondo).
    await tester.tap(find.byKey(const Key('key-5')));

    await scrollTo(tester, find.byKey(const Key('foto-preview')));
    expect(find.byKey(const Key('foto-preview')), findsOneWidget);

    // Salva (PhotoService fa IO reale → runAsync).
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await settleWithRealIo(tester);

    // Tornati al dettaglio: record foto + file su disco + thumb in lista.
    final spesa = (await spesaRepo.getByTrasferta(trasfertaId)).single;
    final foto = await fotoRepo.getBySpesa(spesa.id!);
    expect(foto, isNotNull);
    final file = File(p.join(baseDir.path, foto!.filePath));
    final thumb = File(p.join(baseDir.path, foto.thumbPath));
    expect(file.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);
    expect(find.byKey(Key('tile-thumb-${spesa.id}')), findsOneWidget);

    // Elimina la spesa → file spariti dal filesystem.
    await tester.tap(find.byKey(Key('tile-thumb-${spesa.id}')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('elimina-spesa')));
    await tester.tap(find.byKey(const Key('elimina-spesa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await settleWithRealIo(tester);

    expect(find.text('Nessuna spesa registrata'), findsOneWidget);
    expect(await fotoRepo.getBySpesa(spesa.id!), isNull);
    // Full-size file: never opened by an Image widget → no Windows lock,
    // assert is deterministic. The thumb may stay locked on host Windows
    // (Image handle); its deletion is covered by the controller test.
    expect(file.existsSync(), isFalse);
  });

  testWidgets('scatta: il crop precede l\'OCR e ne riceve il ritaglio',
      (tester) async {
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);

    // Crop screen instead of going straight to the OCR.
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
    expect(orchestrator.calls, isEmpty);

    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(orchestrator.calls, hasLength(1));
    expect(find.text('Nuova spesa'), findsOneWidget);
  });

  testWidgets(
      'scatta: the OCR call and the saved photo both derive from the '
      "cropped path, not the raw capture", (tester) async {
    // Sentinel: a distinct solid color, different from sourceJpg's, so the
    // saved photo's own pixels can be traced back to it specifically —
    // this is the one test that checks what the user actually gets
    // (OCR'd and saved receipt) rather than which code path ran. Real IO,
    // so it must run inside runAsync: a bare await in a testWidgets body
    // never completes under FakeAsync.
    final sentinelPath = p.join(cropDir.path, 'sentinel.jpg');
    await tester.runAsync(() async {
      final sentinel = img.Image(width: 20, height: 20);
      img.fill(sentinel, color: img.ColorRgb8(10, 200, 10));
      await File(sentinelPath).writeAsBytes(img.encodeJpg(sentinel));
    });

    final orchestrator = _FakeOrchestrator();
    await pump(tester,
        orchestrator: orchestrator,
        cropService: _FakeCropService(sentinelPath));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await settleWithRealIo(tester);

    expect(orchestrator.imagePaths, [sentinelPath],
        reason: 'OCR must never see the raw capture once a crop happened');

    await tester.tap(find.byKey(const Key('key-5')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await settleWithRealIo(tester);

    final spesa = (await spesaRepo.getByTrasferta(trasfertaId)).single;
    final foto = await fotoRepo.getBySpesa(spesa.id!);
    final saved = img.decodeImage(
        File(p.join(baseDir.path, foto!.filePath)).readAsBytesSync())!;
    final pixel = saved.getPixel(0, 0);
    expect(pixel.r, closeTo(10, 8));
    expect(pixel.g, closeTo(200, 8));
    expect(pixel.b, closeTo(10, 8));
  });

  testWidgets(
      'scatta: cropping and saving deletes the temporary CROP_ file '
      'afterwards', (tester) async {
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);

    // Actually crop something, so CropService writes a real CROP_ file
    // that differs from the capture's own path.
    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(40, 40));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await settleWithRealIo(tester);

    List<File> cropFiles() => cropDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('CROP_'))
        .toList();
    expect(cropFiles(), hasLength(1),
        reason: 'the drag must have produced a real crop file');

    await tester.tap(find.byKey(const Key('key-5')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await settleWithRealIo(tester);

    expect(cropFiles(), isEmpty,
        reason: 'the crop temp file must be cleaned up once the flow ends');
  });

  testWidgets(
      'scatta: cancelling the OCR progress still deletes the CROP_ file',
      (tester) async {
    // OCR never resolves: the flow reaches the cancellable progress dialog
    // and stops there. The crop temp must not survive that early exit.
    final orchestrator = _FakeOrchestrator()
      ..recognizeImpl =
          (path, engine) => Completer<RecognitionResult>().future;
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);

    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(40, 40));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-conferma')));
    // Flush the crop's real IO without pumpAndSettle: the OCR spinner never
    // stops, so settling would hang. Cycles are enough for crop() to write.
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    List<File> cropFiles() => cropDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('CROP_'))
        .toList();
    expect(cropFiles(), hasLength(1),
        reason: 'the drag must have produced a real crop file');

    await tester.tap(find.byKey(const Key('ocr-annulla')));
    await settleWithRealIo(tester);

    expect(cropFiles(), isEmpty,
        reason: 'a cancelled OCR must not leak the crop temp file');
  });

  testWidgets(
      'scatta: confirming without cropping never deletes the capture '
      'itself', (tester) async {
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);

    // No drag: CropService.crop short-circuits and returns sourceJpg
    // unchanged, so it must never be the thing that gets deleted.
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await settleWithRealIo(tester);

    await tester.tap(find.byKey(const Key('key-5')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await settleWithRealIo(tester);

    expect(File(sourceJpg).existsSync(), isTrue,
        reason: 'crop() returned the source unchanged; deleting it would '
            'destroy the capture, not a temp file');
  });

  testWidgets('scatta: annullare il crop non lancia l\'OCR', (tester) async {
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-annulla')));
    await tester.pumpAndSettle();

    expect(orchestrator.calls, isEmpty);
    expect(find.text('Nuova spesa'), findsNothing);
    expect(find.text('Tokyo'), findsOneWidget); // back on the detail screen
  });

  testWidgets('elimina asks confirmation and cancel keeps the trip',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(PopupMenuButton<DetailAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Eliminare'), findsOneWidget); // dialog

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(await trasfertaRepo.getById(trasfertaId), isNotNull);
  });

  testWidgets('FAB sheet shows the engine selector row (default ML Kit)',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sheet-motore')), findsOneWidget);
    expect(find.text('Motore: ML Kit ▾'), findsOneWidget);
  });

  testWidgets(
      'scatta: fake capture → progress fullscreen → form opens with '
      'OCR banner and pre-filled fields', (tester) async {
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await pumpUntilVisible(tester, find.text('Riconoscimento in corso…'));
    expect(find.text('Riconoscimento in corso…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Nuova spesa'), findsOneWidget);
    expect(find.byKey(const Key('ocr-banner')), findsOneWidget);
    // campo-fornitore is scrolled past the viewport+cache extent (gotcha:
    // plain ListView still needs an explicit scroll for finders further down).
    await scrollTo(tester, find.byKey(const Key('campo-fornitore')));
    expect(find.text('Bar Roma'), findsOneWidget);
    expect(orchestrator.calls, [OcrEngine.mlkit]);
  });

  testWidgets(
      'scatta passes the trasferta linguaDefault as linguaHint to the '
      'orchestrator', (tester) async {
    final srId = await trasfertaRepo.insert(Trasferta(
      nome: 'Beograd',
      dataInizio: DateTime(2026, 7, 10),
      linguaDefault: 'sr',
      createdAt: DateTime(2026, 7, 9),
    ));
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator, id: srId);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(orchestrator.linguaHints, ['sr']);
  });

  testWidgets(
      'scatta infers a ja linguaHint from JPY currency when linguaDefault '
      'is null', (tester) async {
    final jpId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo JPY',
      dataInizio: DateTime(2026, 7, 10),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 9),
    ));
    final orchestrator = _FakeOrchestrator();
    await pump(tester, orchestrator: orchestrator, id: jpId);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(orchestrator.linguaHints, ['ja']);
  });

  testWidgets('annulla during progress: no form opens, back on detail',
      (tester) async {
    final orchestrator = _FakeOrchestrator()
      ..recognizeImpl =
          (path, engine) => Completer<RecognitionResult>().future;
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await pumpUntilVisible(tester, find.text('Riconoscimento in corso…'));
    expect(find.text('Riconoscimento in corso…'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ocr-annulla')));
    await tester.pumpAndSettle();

    expect(find.text('Nuova spesa'), findsNothing);
    expect(find.text('Tokyo'), findsOneWidget);
  });

  testWidgets('Claude fallback to ML Kit shows the SnackBar',
      (tester) async {
    final orchestrator = _FakeOrchestrator()
      ..recognizeImpl = (path, engine) async => RecognitionResult(
            receipt: const ParsedReceipt(engine: OcrEngine.mlkit),
            claudeFallbackToMlkit: true,
          );
    await pump(tester, orchestrator: orchestrator);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(
        find.text('Claude non raggiungibile, usato ML Kit'), findsOneWidget);
  });

  testWidgets(
      'cyrillic gap: empty parsed + lingua sr suggests Claude when available',
      (tester) async {
    final srId = await trasfertaRepo.insert(Trasferta(
      nome: 'Beograd',
      dataInizio: DateTime(2026, 7, 10),
      linguaDefault: 'sr',
      createdAt: DateTime(2026, 7, 9),
    ));
    final orchestrator = _FakeOrchestrator()
      ..recognizeImpl = (path, engine) async => RecognitionResult(
            receipt: const ParsedReceipt(engine: OcrEngine.mlkit),
            claudeFallbackToMlkit: false,
          );
    await pump(tester, orchestrator: orchestrator, id: srId);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(find.textContaining('cirillico'), findsOneWidget);
    expect(find.textContaining('Claude'), findsOneWidget);
  });

  testWidgets(
      'cyrillic gap without a configured API key asks to set it up',
      (tester) async {
    final srId = await trasfertaRepo.insert(Trasferta(
      nome: 'Beograd',
      dataInizio: DateTime(2026, 7, 10),
      linguaDefault: 'sr',
      createdAt: DateTime(2026, 7, 9),
    ));
    final orchestrator = _FakeOrchestrator(claudeAvailableValue: false)
      ..recognizeImpl = (path, engine) async => RecognitionResult(
            receipt: const ParsedReceipt(engine: OcrEngine.mlkit),
            claudeFallbackToMlkit: false,
          );
    await pump(tester, orchestrator: orchestrator, id: srId);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await settleWithRealIo(tester);
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(find.textContaining('cirillico'), findsOneWidget);
    expect(find.textContaining('API key'), findsOneWidget);
  });
}
