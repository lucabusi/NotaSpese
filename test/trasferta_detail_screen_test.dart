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
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/photo/receipt_capture_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake capture: the scanner "returns" a prepared local jpg.
class _FakeCaptureService extends ReceiptCaptureService {
  _FakeCaptureService(this.path);

  final String path;

  @override
  Future<String?> scanWithDocumentScanner() async => path;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late FotoRepository fotoRepo;
  late PhotoService photoService;
  late Directory baseDir;
  late String sourceJpg;
  late int trasfertaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Real IO must happen here: setUp runs outside FakeAsync (see gotcha
    // in spesa_form_screen_test.dart).
    baseDir = await Directory.systemTemp.createTemp('detail_screen');
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
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasfertaDetailScreen(
        controller: TrasfertaDetailController(
            trasfertaId, trasfertaRepo, spesaRepo, fotoRepo, photoService),
        captureService: _FakeCaptureService(sourceJpg),
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
    expect(find.text('Cena'), findsOneWidget);
    // Amount appears twice: per-currency total in the header + spesa tile.
    expect(find.textContaining('3.000'), findsWidgets);
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

    // 📷 Scatta: fake scanner ritorna il jpg preparato → form con preview.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
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
}
