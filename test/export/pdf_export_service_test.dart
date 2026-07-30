import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/pdf_export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip() => Trasferta(
      id: 1,
      nome: 'Tokyo',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      dataFine: DateTime(2026, 7, 5),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

Spesa _spesa({int? id, String? fornitore, double importo = 1000}) => Spesa(
      id: id,
      trasfertaId: 1,
      data: DateTime(2026, 7, 2),
      categoria: Categoria.pranzo,
      fornitore: fornitore,
      importo: importo,
      valuta: 'JPY',
      importoEur: 6.5,
      createdAt: DateTime(2026, 7, 2),
    );

Uint8List _jpg() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfFonts fonts;
  setUpAll(() async {
    fonts = await PdfFonts.load();
  });

  /// Text-showing operator count per page content stream, by inflating the
  /// PDF's Flate streams. "Bytes were produced" says nothing about whether a
  /// page actually drew its content — this does.
  List<int> textOpsPerPage(Uint8List pdf) {
    final counts = <int>[];
    for (var i = 0; i < pdf.length - 6; i++) {
      if (pdf[i] != 0x73 ||
          pdf[i + 1] != 0x74 ||
          pdf[i + 2] != 0x72 ||
          pdf[i + 3] != 0x65 ||
          pdf[i + 4] != 0x61 ||
          pdf[i + 5] != 0x6D) {
        continue;
      }
      var start = i + 6;
      while (start < pdf.length &&
          (pdf[start] == 0x0D || pdf[start] == 0x0A)) {
        start++;
      }
      var end = start;
      while (end < pdf.length - 9) {
        if (pdf[end] == 0x65 &&
            pdf[end + 1] == 0x6E &&
            pdf[end + 2] == 0x64 &&
            pdf[end + 3] == 0x73 &&
            pdf[end + 4] == 0x74 &&
            pdf[end + 5] == 0x72) {
          break;
        }
        end++;
      }
      try {
        final text = latin1.decode(
            ZLibCodec().decode(pdf.sublist(start, end)),
            allowInvalid: true);
        if (!text.contains('BT')) continue;
        counts.add('Tj'.allMatches(text).length +
            'TJ'.allMatches(text).length);
      } on Object {
        // Not a Flate content stream (fonts, images): skip.
      }
    }
    return counts;
  }

  test('cover and table both render their content, not just a heading',
      () async {
    // Regression guard (2026-07-30): a Row with CrossAxisAlignment.stretch
    // inside the cover Column resolved to an infinite box, so it painted
    // nothing AND consumed every sibling's space. The PDF still built, still
    // had four pages, and still threw nothing — the cover was simply blank
    // below its title. Only opening the file revealed it.
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [
        _spesa(id: 1, importo: 1000),
        _spesa(id: 2, importo: 2000),
        _spesa(id: 3, importo: 50),
      ]),
      fotoBytesBySpesaId: const {},
      fonts: fonts,
    );

    final ops = textOpsPerPage(bytes);
    expect(ops.length, greaterThanOrEqualTo(2),
        reason: 'cover + table pages must exist');
    expect(ops.where((n) => n >= 20).length, greaterThanOrEqualTo(2),
        reason: 'both the cover and the table must be populated; the '
            'truncated cover drew only 12 text ops');
  });

  test('produces non-empty bytes without photos', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 1)]),
      fotoBytesBySpesaId: const {},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('produces non-empty bytes with a photo', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 7)]),
      fotoBytesBySpesaId: {7: _jpg()},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('renders a Japanese vendor name without throwing', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 1, fornitore: 'スターバックス')]),
      fotoBytesBySpesaId: const {},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  group('coverEurNote', () {
    test('totaleEur>0 → the converted total, no exclusion note', () {
      final note = coverEurNote(65.0);
      expect(note, startsWith('≈'));
      expect(note, isNot(contains('esclude')));
    });

    test('totaleEur==0 → null, the per-currency rows carry the counts', () {
      expect(coverEurNote(0), isNull);
    });
  });

  group('formatValutaPdf', () {
    test('keeps the symbol for currencies the fonts can draw', () {
      expect(formatValutaPdf(1234.5, 'EUR', const {}), '€ 1.234,50');
      expect(formatValutaPdf(3000, 'JPY', const {}), '¥ 3.000');
    });

    test('falls back to the ISO code for an undrawable symbol', () {
      expect(formatValutaPdf(45, 'AED', const {'AED'}), 'AED 45,00');
    });

    test('the fallback keeps that currency decimal digits', () {
      expect(formatValutaPdf(3000, 'JPY', const {'JPY'}), 'JPY 3.000');
      expect(formatValutaPdf(12.3456, 'KWD', const {'KWD'}), 'KWD 12,346');
    });

    test('an unknown ISO code degrades to two decimals', () {
      expect(formatValutaPdf(10, 'XXX', const {'XXX'}), 'XXX 10,00');
    });
  });

  group('PdfFonts.valuteSenzaSimbolo', () {
    test('flags exactly the Arabic-script symbols the Noto faces lack', () {
      // Read from the real bundled fonts: this is the regression guard for
      // "AED prints as a blank box" (found on a sample export, 2026-07-30).
      expect(fonts.valuteSenzaSimbolo, contains('AED'));
      expect(fonts.valuteSenzaSimbolo, isNot(contains('EUR')));
      expect(fonts.valuteSenzaSimbolo, isNot(contains('JPY')));
      expect(fonts.valuteSenzaSimbolo, isNot(contains('USD')));
    });

    test('is memoised: the same set instance comes back', () {
      expect(identical(fonts.valuteSenzaSimbolo, fonts.valuteSenzaSimbolo),
          isTrue);
    });
  });

  group('statTotaleEur', () {
    test('converted total is shown as an amount', () {
      expect(statTotaleEur(65.0, 0), '€ 65,00');
      expect(statTotaleEur(65.0, 2), '€ 65,00');
    });

    test('nothing converted → em dash, never a misleading € 0,00', () {
      expect(statTotaleEur(0, 3), '—');
    });

    test('a genuinely empty trip still shows a zero amount', () {
      expect(statTotaleEur(0, 0), '€ 0,00');
    });
  });

  group('giorniTrasferta', () {
    Trasferta trip({DateTime? fine}) => Trasferta(
          id: 1,
          nome: 'T',
          dataInizio: DateTime(2026, 7, 1),
          dataFine: fine,
          createdAt: DateTime(2026, 7, 1),
        );

    ReportRow row(DateTime data) => ReportRow(
          spesaId: null,
          data: data,
          categoria: Categoria.pranzo,
          importo: 1,
          valuta: 'EUR',
        );

    test('closed trip: inclusive span between the two dates', () {
      expect(giorniTrasferta(trip(fine: DateTime(2026, 7, 5)), []), 5);
    });

    test('same-day trip counts as one day', () {
      expect(giorniTrasferta(trip(fine: DateTime(2026, 7, 1)), []), 1);
    });

    test('open trip is measured up to its last expense', () {
      expect(
          giorniTrasferta(trip(), [
            row(DateTime(2026, 7, 2)),
            row(DateTime(2026, 7, 4)),
            row(DateTime(2026, 7, 3)),
          ]),
          4);
    });

    test('open trip without expenses collapses to one day', () {
      expect(giorniTrasferta(trip(), []), 1);
    });

    test('an expense dated before the trip start never yields a negative span',
        () {
      expect(giorniTrasferta(trip(), [row(DateTime(2026, 6, 20))]), 1);
    });
  });

  group('fotoCaption', () {
    ReportRow row({String? fornitore}) => ReportRow(
          spesaId: 1,
          data: DateTime(2026, 7, 2),
          categoria: Categoria.pranzo,
          fornitore: fornitore,
          importo: 1000,
          valuta: 'JPY',
          importoEur: 6.5,
        );

    test('with fornitore → 4 parts including the vendor', () {
      final caption = fotoCaption(row(fornitore: 'Sushi Bar'));
      final parts = caption.split(' · ');
      expect(parts, hasLength(4));
      expect(parts, contains('Sushi Bar'));
    });

    test('without fornitore → 3 parts, category not duplicated', () {
      final caption = fotoCaption(row());
      final parts = caption.split(' · ');
      expect(parts, hasLength(3));
      expect(caption.split(Categoria.pranzo.label).length - 1, 1);
    });
  });
}
