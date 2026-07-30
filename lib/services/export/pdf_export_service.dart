import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/currencies.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/trasferta.dart';
import '../../data/models/valuta_breakdown.dart';
import 'trasferta_report.dart';

/// Report palette (mockup "C — Dashboard", blue variant approved 2026-07-30).
/// Kept private to the renderer: these are print colours, unrelated to the
/// app's Material theme, and must not drift into the UI.
class _Palette {
  static const page = PdfColor.fromInt(0xFFF8F9FB);
  static const card = PdfColor.fromInt(0xFFFFFFFF);
  static const ink = PdfColor.fromInt(0xFF1C2436);
  static const sub = PdfColor.fromInt(0xFF66708A);
  static const accent = PdfColor.fromInt(0xFF1857A4);
  static const accentBg = PdfColor.fromInt(0xFFE4ECF8);
  static const line = PdfColor.fromInt(0xFFE2E6EE);
  static const onAccent = PdfColor.fromInt(0xFFFFFFFF);
}

/// Amount for the PDF. Falls back from the currency symbol to the ISO code
/// when the embedded fonts cannot draw that symbol: the bundled Noto faces
/// carry no Arabic, so AED's `د.إ` (and KWD/QAR/SAR) would otherwise print
/// as blank boxes. On screen this never happens — the device font stack
/// covers them — which is why the fallback lives here and not in
/// [formatValuta].
@visibleForTesting
String formatValutaPdf(double value, String code, Set<String> senzaSimbolo) {
  if (!senzaSimbolo.contains(code)) return formatValuta(value, code);
  final decimali = Currency.fromCode(code)?.decimalDigits ?? 2;
  return '$code ${formatImporto(value, decimalDigits: decimali)}';
}

/// Cover EUR line: the converted total, or null when nothing is converted
/// (a "≈ € 0,00" would read as a zeroed trip). What is missing no longer
/// needs a note here — the per-currency rows carry the counts.
@visibleForTesting
String? coverEurNote(double totaleEur) =>
    totaleEur > 0 ? '≈ ${formatEur(totaleEur)}' : null;

/// Headline figure of the cover. An em dash, never "€ 0,00", when nothing
/// could be converted: a zero would read as "this trip cost nothing" rather
/// than "the conversion is missing" (same rule as the trip list header).
@visibleForTesting
String statTotaleEur(double totaleEur, int countSenzaEur) =>
    totaleEur == 0 && countSenzaEur > 0 ? '—' : formatEur(totaleEur);

/// Inclusive day span of the trip. An open trip (`dataFine == null`) is
/// measured up to its last expense, so a report never claims a duration the
/// data does not support; with no expenses at all it collapses to one day.
@visibleForTesting
int giorniTrasferta(Trasferta t, List<ReportRow> righe) {
  var fine = t.dataFine;
  if (fine == null) {
    for (final r in righe) {
      if (fine == null || r.data.isAfter(fine)) fine = r.data;
    }
  }
  if (fine == null || fine.isBefore(t.dataInizio)) return 1;
  return fine.difference(t.dataInizio).inDays + 1;
}

/// One cover row per currency: how many spese, their total, and the EUR
/// equivalent. The EUR tail is dropped on a EUR row (it would repeat the
/// amount) and when nothing in that currency is converted.
@visibleForTesting
String rigaValuta(ValutaBreakdown b, [Set<String> senzaSimbolo = const {}]) {
  final spese = b.count == 1 ? '1 spesa' : '${b.count} spese';
  final eur = b.valuta == 'EUR' || b.totaleEur == 0
      ? ''
      : ' · ≈ ${formatEur(b.totaleEur)}';
  final totale = formatValutaPdf(b.totale, b.valuta, senzaSimbolo);
  return '${b.valuta} · $spese · $totale$eur';
}

/// Photo caption: `data · fornitore · importo valuta · categoria`. When
/// [ReportRow.fornitore] is missing, that slot is omitted entirely rather
/// than substituted with the category (which would then appear twice).
@visibleForTesting
String fotoCaption(ReportRow r, [Set<String> senzaSimbolo = const {}]) => [
      formatDate(r.data),
      if (r.fornitore != null && r.fornitore!.isNotEmpty) r.fornitore!,
      formatValutaPdf(r.importo, r.valuta, senzaSimbolo),
      r.categoria.label,
    ].join(' · ');

/// Loaded PDF fonts: Latin base + bold, Japanese fallback. Loading touches
/// the asset bundle, so it is kept out of [PdfExportService] (pure renderer).
class PdfFonts {
  PdfFonts({
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

  /// ISO codes whose symbol none of the embedded faces can draw, read from
  /// the fonts' own cmap rather than guessed: a hardcoded list would rot the
  /// moment a font asset or a [Currency] symbol changes. Computed once per
  /// export; the parse is the same work the pdf package does when embedding.
  Set<String> get valuteSenzaSimbolo => _senzaSimbolo ??= _computeSenzaSimbolo();
  Set<String>? _senzaSimbolo;

  Set<String> _computeSenzaSimbolo() {
    final disegnabili = <int>{};
    for (final font in [regular, jp]) {
      if (font is pw.TtfFont) {
        disegnabili.addAll(TtfParser(font.data).charToGlyphIndexMap.keys);
      }
    }
    // No parsable font (a stubbed PdfFonts in a test): assume every symbol
    // is fine rather than degrade every amount to its ISO code.
    if (disegnabili.isEmpty) return const {};
    return {
      for (final c in Currency.values)
        if (!c.symbol.runes.every(disegnabili.contains)) c.code,
    };
  }
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
    final senzaSimbolo = fonts.valuteSenzaSimbolo;

    doc.addPage(pw.Page(
      pageTheme: _pageTheme(PdfPageFormat.a4, theme),
      build: (context) => _cover(report, senzaSimbolo),
    ));

    doc.addPage(pw.MultiPage(
      pageTheme: _pageTheme(PdfPageFormat.a4, theme),
      build: (context) => [_table(report, senzaSimbolo)],
    ));

    final conFoto = report.righe
        .where((r) =>
            r.spesaId != null && fotoBytesBySpesaId.containsKey(r.spesaId))
        .toList();
    for (var i = 0; i < conFoto.length; i += 2) {
      final end = (i + 2) < conFoto.length ? i + 2 : conFoto.length;
      final coppia = conFoto.sublist(i, end);
      doc.addPage(pw.Page(
        pageTheme: _pageTheme(PdfPageFormat.a4.landscape, theme),
        build: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final r in coppia)
              pw.Expanded(
                child: _fotoBlock(
                    r, fotoBytesBySpesaId[r.spesaId]!, senzaSimbolo),
              ),
          ],
        ),
      ));
    }

    return doc.save();
  }

  /// Tinted paper: the cards only read as cards against a non-white page.
  pw.PageTheme _pageTheme(PdfPageFormat format, pw.ThemeData theme) =>
      pw.PageTheme(
        pageFormat: format,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _Palette.page),
        ),
      );

  // ---------- cover ----------

  pw.Widget _cover(TrasfertaReport report, Set<String> senzaSimbolo) {
    final t = report.trasferta;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _badge('Trasferta'),
        pw.SizedBox(height: 10),
        pw.Text(
          t.nome,
          style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: _Palette.ink),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (t.luogo != null && t.luogo!.isNotEmpty) _chip(t.luogo!),
            _chip(formatDateRange(t.dataInizio, t.dataFine)),
          ],
        ),
        pw.SizedBox(height: 18),
        _statRow(report),
        pw.SizedBox(height: 18),
        _sectionTitle('Per valuta'),
        pw.SizedBox(height: 6),
        _card(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final b in report.breakdown) ...[
                if (b != report.breakdown.first) pw.SizedBox(height: 4),
                pw.Text(rigaValuta(b, senzaSimbolo),
                    style: const pw.TextStyle(fontSize: 11, color: _Palette.ink)),
              ],
              if (report.breakdown.isEmpty)
                pw.Text('Nessuna spesa registrata',
                    style: const pw.TextStyle(fontSize: 11, color: _Palette.sub)),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        _sectionTitle('Per categoria (${report.valutaCategorie})'),
        pw.SizedBox(height: 6),
        _categoryBars(report, senzaSimbolo),
        if (report.countSenzaEur > 0) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            report.countSenzaEur == 1
                ? '1 spesa senza conversione EUR'
                : '${report.countSenzaEur} spese senza conversione EUR',
            // No italic: the bundle ships no italic Noto face, so the pdf
            // package silently falls back to built-in Helvetica-Oblique,
            // which has no Unicode support.
            style: const pw.TextStyle(fontSize: 9, color: _Palette.sub),
          ),
        ],
      ],
    );
  }

  pw.Widget _statRow(TrasfertaReport report) {
    final giorni = giorniTrasferta(report.trasferta, report.righe);
    // No CrossAxisAlignment.stretch here: a Column hands its children an
    // unbounded height, so a stretching Row resolves to an infinite box —
    // it then paints nothing AND swallows the space of every sibling below
    // it, silently truncating the cover. The cards are equal-height anyway
    // because they hold the same two-line structure.
    return pw.Row(
      children: [
        pw.Expanded(
          flex: 3,
          child: _stat(
              statTotaleEur(report.totaleEur, report.countSenzaEur),
              'Totale ≈ EUR',
              emphasised: true),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 2,
          child: _stat('${report.righe.length}',
              report.righe.length == 1 ? 'Spesa' : 'Spese'),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 2,
          child: _stat('$giorni', giorni == 1 ? 'Giorno' : 'Giorni'),
        ),
      ],
    );
  }

  pw.Widget _stat(String value, String label, {bool emphasised = false}) =>
      _card(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: emphasised ? 17 : 14,
                fontWeight: pw.FontWeight.bold,
                color: _Palette.accent,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(label.toUpperCase(),
                style: const pw.TextStyle(fontSize: 7, color: _Palette.sub)),
          ],
        ),
      );

  /// Proportional bars, largest first. Widths come from integer flex weights
  /// rather than absolute sizes, so the bars adapt to the page width.
  pw.Widget _categoryBars(TrasfertaReport report, Set<String> senzaSimbolo) {
    final voci = report.totaliPerCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (voci.isEmpty) {
      return _card(
        child: pw.Text('Nessuna spesa registrata',
            style: const pw.TextStyle(fontSize: 11, color: _Palette.sub)),
      );
    }
    final massimo = voci.first.value;
    return _card(
      child: pw.Column(
        children: [
          for (final e in voci) ...[
            if (e != voci.first) pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.SizedBox(
                  width: 82,
                  child: pw.Text(e.key.label,
                      style: const pw.TextStyle(
                          fontSize: 9, color: _Palette.ink)),
                ),
                pw.Expanded(child: _bar(e.value, massimo)),
                pw.SizedBox(width: 8),
                pw.SizedBox(
                  width: 78,
                  child: pw.Text(
                    formatValutaPdf(
                        e.value, report.valutaCategorie, senzaSimbolo),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _Palette.ink),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _bar(double value, double massimo) {
    // clamp(1, 100): a non-zero amount always leaves a visible sliver, so a
    // tiny expense never renders as "nothing spent".
    final pieno =
        massimo <= 0 ? 1 : (value / massimo * 100).round().clamp(1, 100);
    final vuoto = 100 - pieno;
    return pw.Container(
      height: 7,
      decoration: pw.BoxDecoration(
        color: _Palette.accentBg,
        borderRadius: pw.BorderRadius.circular(3.5),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: pieno,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: _Palette.accent,
                borderRadius: pw.BorderRadius.circular(3.5),
              ),
            ),
          ),
          if (vuoto > 0) pw.Expanded(flex: vuoto, child: pw.SizedBox()),
        ],
      ),
    );
  }

  // ---------- expense table ----------

  /// Note: no rounded outer card here, unlike the mockup. The table has to
  /// flow across pages (MultiPage) and a clipping wrapper cannot span a page
  /// break — it would force the whole table onto one page and overflow.
  pw.Widget _table(TrasfertaReport report, Set<String> senzaSimbolo) {
    pw.Widget cell(
      String text, {
      bool header = false,
      bool bold = false,
      PdfColor color = _Palette.ink,
      pw.Alignment align = pw.Alignment.centerLeft,
    }) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            header ? text.toUpperCase() : text,
            style: pw.TextStyle(
              fontSize: header ? 7.5 : 9,
              fontWeight:
                  header || bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _Palette.accentBg),
        children: [
          cell('Data', header: true, color: _Palette.accent),
          cell('Categoria', header: true, color: _Palette.accent),
          cell('Fornitore', header: true, color: _Palette.accent),
          cell('Importo',
              header: true,
              color: _Palette.accent,
              align: pw.Alignment.centerRight),
          cell('Val.', header: true, color: _Palette.accent),
          cell('≈ EUR',
              header: true,
              color: _Palette.accent,
              align: pw.Alignment.centerRight),
        ],
      ),
      for (final (i, r) in report.righe.indexed)
        pw.TableRow(
          decoration: pw.BoxDecoration(
              color: i.isEven ? _Palette.card : _Palette.page),
          children: [
            cell(formatDate(r.data)),
            cell(r.categoria.label),
            cell(r.fornitore ?? ''),
            cell(formatValutaPdf(r.importo, r.valuta, senzaSimbolo),
                align: pw.Alignment.centerRight),
            cell(r.valuta),
            cell(r.importoEur == null ? '' : formatEur(r.importoEur!),
                align: pw.Alignment.centerRight),
          ],
        ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _Palette.accent),
        children: [
          cell('', color: _Palette.onAccent),
          cell('', color: _Palette.onAccent),
          cell('', color: _Palette.onAccent),
          cell('', color: _Palette.onAccent),
          cell('Totale',
              bold: true,
              color: _Palette.onAccent,
              align: pw.Alignment.centerRight),
          cell(formatEur(report.totaleEur),
              bold: true,
              color: _Palette.onAccent,
              align: pw.Alignment.centerRight),
        ],
      ),
    ];

    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(width: 0.5, color: _Palette.line),
      ),
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

  // ---------- receipt photos ----------

  pw.Widget _fotoBlock(
          ReportRow r, Uint8List bytes, Set<String> senzaSimbolo) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: _card(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: _Palette.accentBg,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                fotoCaption(r, senzaSimbolo),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8.5, color: _Palette.sub),
              ),
            ],
          ),
        ),
      );

  // ---------- shared chrome ----------

  pw.Widget _card({required pw.Widget child, pw.EdgeInsets? padding}) =>
      pw.Container(
        width: double.infinity,
        padding: padding ?? const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _Palette.card,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: _Palette.line, width: 0.7),
        ),
        child: child,
      );

  pw.Widget _badge(String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(
          color: _Palette.accentBg,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Text(
          text.toUpperCase(),
          style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: _Palette.accent),
        ),
      );

  pw.Widget _chip(String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(
          color: _Palette.card,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _Palette.line, width: 0.7),
        ),
        child: pw.Text(text,
            style: const pw.TextStyle(fontSize: 8.5, color: _Palette.sub)),
      );

  pw.Widget _sectionTitle(String text) => pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _Palette.sub),
      );
}
