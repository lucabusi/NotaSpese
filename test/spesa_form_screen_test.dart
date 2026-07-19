import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/foto.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/ui/spese/spesa_form_screen.dart';
import 'package:path/path.dart' as p;

import 'fakes/fake_exchange_service.dart';

/// Shared fixture: 1200 JPY parsed from a receipt (fase 6 EUR conversion
/// tests).
ParsedReceipt parsedJpy1200() => ParsedReceipt(
      importo: 1200,
      valuta: 'JPY',
      data: DateTime(2026, 7, 10),
      fornitore: 'Lawson',
      lingua: 'ja',
      engine: OcrEngine.mlkit,
      rawText: 'x',
    );

/// Shared fixture: an existing JPY expense with no stored tassoCambio
/// (manual/no conversion), used by the "no auto-recalc on edit" tests.
Spesa spesaJpyEsistente({double importo = 1200}) => Spesa(
      id: 7,
      trasfertaId: 1,
      data: DateTime(2026, 7, 10),
      categoria: Categoria.pranzo,
      fornitore: 'Lawson',
      importo: importo,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 10, 9),
    );

void main() {
  Spesa? saved;
  String? savedNuovaFoto;
  var savedRimuoviFoto = false;
  var deleted = false;
  late Directory tempDir;
  late String pickedPath;
  late String pendingPath;
  late String thumbAbsPath;

  Future<String> writeJpg(String name) async {
    final im = img.Image(width: 64, height: 48);
    img.fill(im, color: img.ColorRgb8(90, 160, 60));
    final path = p.join(tempDir.path, name);
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(img.encodeJpg(im));
    return path;
  }

  // GOTCHA: real file IO must happen HERE (setUp runs outside FakeAsync).
  // Awaiting real IO inside a testWidgets body never resumes — FakeAsync
  // holds the microtask — and the test hangs with no timeout.
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spesa_form');
    pickedPath = await writeJpg('picked.jpg');
    pendingPath = await writeJpg('pending.jpg');
    thumbAbsPath = await writeJpg('thumbnails/thumb.jpg');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<void> pumpForm(
    WidgetTester tester, {
    String valutaDefault = 'EUR',
    Spesa? initial,
    Foto? initialFoto,
    String? pendingFotoSourcePath,
    Future<String?> Function()? onPickFoto,
    Future<String> Function(String rel)? photoPathResolver,
    bool withDelete = false,
    ParsedReceipt? parsed,
    Future<ParsedReceipt?> Function()? onRetryOtherEngine,
    FakeExchangeService? exchange,
    Future<void> Function(Spesa s, {String? nuovaFoto, bool rimuoviFoto})?
        onSave,
  }) async {
    saved = null;
    savedNuovaFoto = null;
    savedRimuoviFoto = false;
    deleted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SpesaFormScreen(
              trasfertaId: 1,
              valutaDefault: valutaDefault,
              initial: initial,
              initialFoto: initialFoto,
              pendingFotoSourcePath: pendingFotoSourcePath,
              onPickFoto: onPickFoto,
              photoPathResolver: photoPathResolver,
              parsed: parsed,
              onRetryOtherEngine: onRetryOtherEngine,
              exchange: exchange ?? FakeExchangeService(),
              onSave: onSave ??
                  (s, {nuovaFoto, rimuoviFoto = false}) async {
                    saved = s;
                    savedNuovaFoto = nuovaFoto;
                    savedRimuoviFoto = rimuoviFoto;
                  },
              onDelete: withDelete ? () async => deleted = true : null,
            ),
          )),
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  // The form's ListView; TextFields have inner Scrollables, so the default
  // find.byType(Scrollable) of scrollUntilVisible would be ambiguous.
  // scrollUntilVisible stops as soon as the widget EXISTS (it may still sit
  // half off-screen and fail hit tests), so finish with ensureVisible.
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

  testWidgets('saves manual expense; EUR currency auto-fills importo_eur',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('key-1')));
    await tester.tap(find.byKey(const Key('key-2')));
    await tester.tap(find.byKey(const Key('key-comma')));
    await tester.tap(find.byKey(const Key('key-5')));
    await tester.pump();
    expect(find.text('12,5'), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('chip-cena')));
    await tester.tap(find.byKey(const Key('chip-cena')));
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    expect(saved!.importo, 12.5);
    expect(saved!.valuta, 'EUR');
    expect(saved!.importoEur, 12.5);
    expect(saved!.categoria, Categoria.cena);
    expect(saved!.trasfertaId, 1);
    expect(saved!.ocrEngine, isNull);
    expect(savedNuovaFoto, isNull);
    expect(savedRimuoviFoto, isFalse);
    expect(find.text('apri'), findsOneWidget); // form chiuso
  });

  testWidgets('currency switch to JPY: no decimals, no auto EUR',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('campo-valuta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('valuta-JPY')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('key-3')));
    await tester.tap(find.byKey(const Key('key-comma'))); // no-op (0 decimali)
    await tester.tap(find.byKey(const Key('key-5')));
    await tester.pump();
    expect(find.text('35'), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    expect(saved!.valuta, 'JPY');
    expect(saved!.importo, 35);
    expect(saved!.importoEur, isNull);
  });

  testWidgets('empty amount blocks save with a snackbar', (tester) async {
    await pumpForm(tester);

    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pump();

    expect(saved, isNull);
    expect(find.textContaining('Inserisci un importo'), findsOneWidget);
  });

  testWidgets('edit mode prefills fields; delete asks confirmation',
      (tester) async {
    final spesa = Spesa(
      id: 7,
      trasfertaId: 1,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.taxi,
      fornitore: 'Taxi Roma',
      importo: 25.5,
      valuta: 'EUR',
      importoEur: 25.5,
      createdAt: DateTime(2026, 7, 11, 9),
    );
    await pumpForm(tester, initial: spesa, withDelete: true);

    expect(find.text('Modifica spesa'), findsOneWidget);
    expect(find.text('25,5'), findsOneWidget);
    await scrollTo(tester, find.text('Taxi Roma'));
    expect(find.text('Taxi Roma'), findsOneWidget);

    // Salva preserva id e createdAt.
    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(saved!.id, 7);
    expect(saved!.createdAt, DateTime(2026, 7, 11, 9));

    // Riapre per il percorso elimina.
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('elimina-spesa')));
    await tester.tap(find.byKey(const Key('elimina-spesa')));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare la spesa?'), findsOneWidget);

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('photo picked from onPickFoto shows preview and rides onSave',
      (tester) async {
    await pumpForm(tester, onPickFoto: () async => pickedPath);

    // Importo digitato PRIMA dello scroll: la ListView lazy smonta il
    // keypad quando si scorre in fondo al form.
    await tester.tap(find.byKey(const Key('key-9')));

    await scrollTo(tester, find.byKey(const Key('foto-area-aggiungi')));
    await tester.tap(find.byKey(const Key('foto-area-aggiungi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('foto-preview')), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    expect(savedNuovaFoto, pickedPath);
    expect(savedRimuoviFoto, isFalse);
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('pending capture preset shows preview; removable',
      (tester) async {
    await pumpForm(tester, pendingFotoSourcePath: pendingPath);

    await scrollTo(tester, find.byKey(const Key('foto-preview')));
    expect(find.byKey(const Key('foto-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('foto-rimuovi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('foto-area-aggiungi')), findsOneWidget);
  });

  testWidgets('existing photo: thumb shown, rimuovi sets rimuoviFoto',
      (tester) async {
    final spesa = Spesa(
      id: 7,
      trasfertaId: 1,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 10,
      valuta: 'EUR',
      importoEur: 10,
      createdAt: DateTime(2026, 7, 11, 9),
    );
    final foto = Foto(
      id: 3,
      spesaId: 7,
      filePath: 'IMG_1.jpg',
      thumbPath: 'thumbnails/thumb.jpg',
      createdAt: DateTime(2026, 7, 11, 9),
    );
    await pumpForm(
      tester,
      initial: spesa,
      initialFoto: foto,
      photoPathResolver: (rel) async =>
          rel == foto.thumbPath ? thumbAbsPath : p.join(tempDir.path, rel),
    );

    await scrollTo(tester, find.byKey(const Key('foto-thumb')));
    expect(find.byKey(const Key('foto-thumb')), findsOneWidget);

    await tester.tap(find.byKey(const Key('foto-rimuovi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('foto-area-aggiungi')), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(savedRimuoviFoto, isTrue);
    expect(savedNuovaFoto, isNull);
  });

  group('OCR pre-fill, banner, retry', () {
    testWidgets('parsed prefills fields and shows success banner with engine',
        (tester) async {
      final parsed = ParsedReceipt(
        importo: 42.5,
        valuta: 'USD',
        data: DateTime(2026, 7, 10),
        fornitore: 'Hotel Test',
        engine: OcrEngine.mlkit,
      );
      await pumpForm(tester, parsed: parsed);

      expect(find.byKey(const Key('ocr-banner')), findsOneWidget);
      expect(find.textContaining('ML Kit'), findsOneWidget);
      expect(find.text('42,5'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);

      await scrollTo(tester, find.text('Hotel Test'));
      expect(find.text('Hotel Test'), findsOneWidget);
    });

    testWidgets('parsed.isEmpty shows warning banner', (tester) async {
      const parsed = ParsedReceipt(engine: OcrEngine.claude);
      await pumpForm(tester, parsed: parsed);

      expect(find.byKey(const Key('ocr-banner')), findsOneWidget);
      expect(find.textContaining('Nessun dato riconosciuto'), findsOneWidget);
    });

    testWidgets('no parsed: no banner (regression)', (tester) async {
      await pumpForm(tester);
      expect(find.byKey(const Key('ocr-banner')), findsNothing);
    });

    testWidgets(
        'retry EUR->JPY: currency-triggered decimal truncation does not '
        'mask the untouched importo overwrite', (tester) async {
      final parsed = ParsedReceipt(
        importo: 20.55,
        valuta: 'EUR',
        engine: OcrEngine.mlkit,
      );
      final retryResult = ParsedReceipt(
        importo: 1500,
        valuta: 'JPY',
        engine: OcrEngine.claude,
      );
      await pumpForm(
        tester,
        parsed: parsed,
        onRetryOtherEngine: () async => retryResult,
      );

      expect(find.text('20,55'), findsOneWidget);

      // No user interaction: both importo and valuta stay untouched.
      await tester.tap(find.byKey(const Key('ocr-riprova')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riprova con altro motore'));
      await tester.pumpAndSettle();

      expect(find.text('1500'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
      expect(find.textContaining('Claude'), findsOneWidget);
    });

    testWidgets('save persists ocrEngine from parsed engine', (tester) async {
      final parsed = ParsedReceipt(importo: 10, engine: OcrEngine.mlkit);
      await pumpForm(tester, parsed: parsed);

      await scrollTo(tester, find.byKey(const Key('salva-spesa')));
      await tester.tap(find.byKey(const Key('salva-spesa')));
      await tester.pumpAndSettle();

      expect(saved!.ocrEngine, 'mlkit');
    });

    testWidgets(
        'retry with other engine overwrites only untouched fields',
        (tester) async {
      final parsed = ParsedReceipt(
        importo: 20,
        valuta: 'EUR',
        data: DateTime(2026, 7, 1),
        fornitore: 'A',
        engine: OcrEngine.mlkit,
      );
      final retryResult = ParsedReceipt(
        importo: 99,
        valuta: 'USD',
        data: DateTime(2026, 7, 5),
        fornitore: 'B',
        engine: OcrEngine.claude,
      );
      await pumpForm(
        tester,
        parsed: parsed,
        onRetryOtherEngine: () async => retryResult,
      );

      expect(find.text('20'), findsOneWidget);

      // Touch importo (user edits it BEFORE retrying).
      await tester.tap(find.byKey(const Key('key-1')));
      await tester.pump();
      expect(find.text('201'), findsOneWidget);

      // Open banner menu and select retry.
      await tester.tap(find.byKey(const Key('ocr-riprova')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riprova con altro motore'));
      await tester.pumpAndSettle();

      // Touched field preserved.
      expect(find.text('201'), findsOneWidget);
      // Untouched fields overwritten from retry result.
      expect(find.text('USD'), findsOneWidget);
      expect(find.textContaining('Claude'), findsOneWidget);

      await scrollTo(tester, find.text('B'));
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets(
        'save persists ocrEngine from the POST-RETRY result, not the '
        'original parsed engine', (tester) async {
      final parsed = ParsedReceipt(importo: 10, engine: OcrEngine.mlkit);
      final retryResult = ParsedReceipt(importo: 10, engine: OcrEngine.claude);
      await pumpForm(
        tester,
        parsed: parsed,
        onRetryOtherEngine: () async => retryResult,
      );

      await tester.tap(find.byKey(const Key('ocr-riprova')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riprova con altro motore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Claude'), findsOneWidget);

      await scrollTo(tester, find.byKey(const Key('salva-spesa')));
      await tester.tap(find.byKey(const Key('salva-spesa')));
      await tester.pumpAndSettle();

      expect(saved!.ocrEngine, 'claude');
    });
  });

  group('conversione EUR live', () {
    testWidgets('pre-fill OCR + debounce → campo EUR AUTO con tasso',
        (tester) async {
      final exchange = FakeExchangeService(rate: 0.0061);
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: exchange,
          parsed: parsedJpy1200());
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.text('7,32'), findsOneWidget); // 1200 * 0.0061 nel campo EUR
      expect(find.textContaining('AUTO · 1 JPY ='), findsOneWidget);
      expect(exchange.calls, 1);
    });

    testWidgets('salvataggio AUTO persiste tassoCambio', (tester) async {
      Spesa? localSaved;
      final exchange = FakeExchangeService(rate: 0.0061);
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: exchange,
          parsed: parsedJpy1200(),
          onSave: (s, {nuovaFoto, rimuoviFoto = false}) async =>
              localSaved = s);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await scrollTo(tester, find.byKey(const Key('salva-spesa')));
      await tester.tap(find.byKey(const Key('salva-spesa')));
      await tester.pumpAndSettle();
      expect(localSaved!.tassoCambio, 0.0061);
      expect(localSaved!.importoEur, closeTo(7.32, 0.001));
    });

    testWidgets('edit manuale del campo EUR toglie AUTO e azzera tasso',
        (tester) async {
      Spesa? localSaved;
      final exchange = FakeExchangeService(rate: 0.0061);
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: exchange,
          parsed: parsedJpy1200(),
          onSave: (s, {nuovaFoto, rimuoviFoto = false}) async =>
              localSaved = s);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await scrollTo(tester, find.byKey(const Key('campo-importo-eur')));
      await tester.enterText(
          find.byKey(const Key('campo-importo-eur')), '8,00');
      await tester.pump();
      expect(find.textContaining('AUTO ·'), findsNothing);
      await scrollTo(tester, find.byKey(const Key('salva-spesa')));
      await tester.tap(find.byKey(const Key('salva-spesa')));
      await tester.pumpAndSettle();
      expect(localSaved!.tassoCambio, isNull);
      expect(localSaved!.importoEur, 8.0);
    });

    testWidgets('offline: campo resta vuoto, salvataggio senza EUR ok',
        (tester) async {
      Spesa? localSaved;
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: FakeExchangeService(rate: null),
          parsed: parsedJpy1200(),
          onSave: (s, {nuovaFoto, rimuoviFoto = false}) async =>
              localSaved = s);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.textContaining('AUTO ·'), findsNothing);
      await scrollTo(tester, find.byKey(const Key('salva-spesa')));
      await tester.tap(find.byKey(const Key('salva-spesa')));
      await tester.pumpAndSettle();
      expect(localSaved!.importoEur, isNull);
      expect(localSaved!.tassoCambio, isNull);
    });

    testWidgets('spesa esistente: nessuna conversione automatica',
        (tester) async {
      final exchange = FakeExchangeService(rate: 0.0061);
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: exchange,
          initial: spesaJpyEsistente());
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(exchange.calls, 0);
    });

    testWidgets('ricalcola sovrascrive anche il valore manuale',
        (tester) async {
      final exchange = FakeExchangeService(rate: 0.0065);
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: exchange,
          initial: spesaJpyEsistente(importo: 1000));
      await scrollTo(tester, find.byKey(const Key('campo-importo-eur')));
      await tester.enterText(
          find.byKey(const Key('campo-importo-eur')), '9,99');
      await scrollTo(tester, find.byKey(const Key('eur-ricalcola')));
      await tester.tap(find.byKey(const Key('eur-ricalcola')));
      await tester.pumpAndSettle();
      expect(find.text('6,50'), findsOneWidget); // 1000 * 0.0065
      expect(find.textContaining('AUTO · 1 JPY ='), findsOneWidget);
    });

    testWidgets('ricalcola con tasso non disponibile mostra snackbar',
        (tester) async {
      await pumpForm(tester,
          valutaDefault: 'JPY',
          exchange: FakeExchangeService(rate: null),
          initial: spesaJpyEsistente());
      await scrollTo(tester, find.byKey(const Key('eur-ricalcola')));
      await tester.tap(find.byKey(const Key('eur-ricalcola')));
      await tester.pumpAndSettle();
      expect(find.text('Tasso non disponibile'), findsOneWidget);
    });
  });
}
