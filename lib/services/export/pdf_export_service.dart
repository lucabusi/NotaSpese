import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import 'trasferta_report.dart';

/// Cover EUR line text, consistent with the CSV exclusion note (gated on
/// [countSenzaEur] alone, not on [totaleEur]): a trip entirely in a
/// non-convertible currency has `totaleEur == 0` but must still surface the
/// exclusion note instead of silently dropping it.
@visibleForTesting
String? coverEurNote(double totaleEur, int countSenzaEur) {
  if (totaleEur > 0) {
    return '≈ ${formatEur(totaleEur)}'
        '${countSenzaEur > 0 ? ' (esclude $countSenzaEur spese non convertite)' : ''}';
  }
  if (countSenzaEur > 0) {
    return 'esclude $countSenzaEur spese non convertite';
  }
  return null;
}

/// Photo caption: `data · fornitore · importo valuta · categoria`. When
/// [ReportRow.fornitore] is missing, that slot is omitted entirely rather
/// than substituted with the category (which would then appear twice).
@visibleForTesting
String fotoCaption(ReportRow r) => [
      formatDate(r.data),
      if (r.fornitore != null && r.fornitore!.isNotEmpty) r.fornitore!,
      formatValuta(r.importo, r.valuta),
      r.categoria.label,
    ].join(' · ');

/// Loaded PDF fonts: Latin base + bold, Japanese fallback. Loading touches
/// the asset bundle, so it is kept out of [PdfExportService] (pure renderer).
class PdfFonts {
  const PdfFonts({
    required this.regular,
    required this.bold,
    required this.jp,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font jp;

  static Future<PdfFonts> load() async => PdfFonts(
        regular:
            pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
        jp: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansJP-Regular.ttf')),
      );
}

/// Renders a [TrasfertaReport] to a shareable PDF: cover (totals) → expense
/// table → landscape photo pages (2 receipts each). Pure: photo bytes and
/// fonts are injected; no filesystem/DB access.
class PdfExportService {
  const PdfExportService();

  Future<Uint8List> build(
    TrasfertaReport report, {
    required Map<int, Uint8List> fotoBytesBySpesaId,
    required PdfFonts fonts,
  }) async {
    final theme = pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
      fontFallback: [fonts.jp],
    );
    final doc = pw.Document(theme: theme);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => _cover(report),
    ));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [_table(report)],
    ));

    final conFoto = report.righe
        .where((r) =>
            r.spesaId != null && fotoBytesBySpesaId.containsKey(r.spesaId))
        .toList();
    for (var i = 0; i < conFoto.length; i += 2) {
      final end = (i + 2) < conFoto.length ? i + 2 : conFoto.length;
      final coppia = conFoto.sublist(i, end);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final r in coppia)
              pw.Expanded(
                child: _fotoBlock(r, fotoBytesBySpesaId[r.spesaId]!),
              ),
          ],
        ),
      ));
    }

    return doc.save();
  }

  pw.Widget _cover(TrasfertaReport report) {
    final t = report.trasferta;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(t.nome,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          [
            if (t.luogo != null && t.luogo!.isNotEmpty) t.luogo,
            formatDateRange(t.dataInizio, t.dataFine),
            '${report.righe.length} spese',
          ].join(' · '),
          style: const pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 20),
        pw.Text('TOTALI',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final e in report.totaliPerValuta.entries)
          pw.Text(formatValuta(e.value, e.key), style: const pw.TextStyle(fontSize: 12)),
        if (coverEurNote(report.totaleEur, report.countSenzaEur) case final note?) ...[
          pw.SizedBox(height: 2),
          pw.Text(note, style: const pw.TextStyle(fontSize: 11)),
        ],
        pw.SizedBox(height: 20),
        pw.Text('PER CATEGORIA (${report.valutaCategorie})',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final e in (report.totaliPerCategoria.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value))))
          pw.Text('${e.key.label}: ${formatValuta(e.value, report.valutaCategorie)}',
              style: const pw.TextStyle(fontSize: 12)),
      ],
    );
  }

  pw.Widget _table(TrasfertaReport report) {
    pw.Widget cell(String text, {bool header = false, pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(repeat: true, children: [
        cell('Data', header: true),
        cell('Categoria', header: true),
        cell('Fornitore', header: true),
        cell('Importo', header: true, align: pw.Alignment.centerRight),
        cell('Valuta', header: true),
        cell('≈ EUR', header: true, align: pw.Alignment.centerRight),
      ]),
      for (final r in report.righe)
        pw.TableRow(children: [
          cell(formatDate(r.data)),
          cell(r.categoria.label),
          cell(r.fornitore ?? ''),
          cell(formatValuta(r.importo, r.valuta), align: pw.Alignment.centerRight),
          cell(r.valuta),
          cell(r.importoEur == null ? '' : formatEur(r.importoEur!),
              align: pw.Alignment.centerRight),
        ]),
      pw.TableRow(children: [
        cell(''),
        cell(''),
        cell(''),
        cell(''),
        cell('TOTALE', header: true, align: pw.Alignment.centerRight),
        cell(formatEur(report.totaleEur),
            header: true, align: pw.Alignment.centerRight),
      ]),
    ];

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(2.6),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1),
        5: pw.FlexColumnWidth(1.4),
      },
      children: rows,
    );
  }

  pw.Widget _fotoBlock(ReportRow r, Uint8List bytes) {
    final didascalia = fotoCaption(r);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 6),
          pw.Text(didascalia,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
