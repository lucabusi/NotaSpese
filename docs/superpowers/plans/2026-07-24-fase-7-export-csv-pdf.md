# Fase 7 — Export CSV / PDF — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a single trip's expenses to CSV and PDF, shared via the Android share sheet, from two menu voices in the trip detail screen.

**Architecture:** A pure-Dart `TrasfertaReport` aggregates/sorts the expenses once; two thin renderers consume it — `CsvExportService` (report → String) and `PdfExportService` (report + photo bytes → `Uint8List`). An `ExportService` writes the bytes to a temp file and shares it. The renderers do no I/O and are host-testable; photo bytes and fonts are resolved by the caller and injected.

**Tech Stack:** Dart/Flutter, packages `csv` and `pdf` (new), `share_plus` (already present), Noto Sans + Noto Sans JP TTF fonts bundled as assets.

Reference spec: `docs/superpowers/specs/2026-07-24-fase-7-export-csv-pdf-design.md`.

## Global Constraints

- Comments/code/commits in English; UI strings in Italian (project convention).
- Surgical changes only; match existing style. No unrequested refactoring.
- Commit at the end of each task. Never `--force`, `reset --hard`, or skip hooks.
- `flutter analyze` must stay at zero issues.
- CSV: UTF-8 **with BOM** (`﻿`), field separator `;`, line ending `\r\n`, decimals with comma.
- PDF: cover (A4 portrait) → table (A4 portrait) → photo pages (A4 landscape, 2 receipts/page); Japanese vendor names must render (Noto Sans JP fallback). `printing` package is NOT used.
- Money formatted with 2 decimals; per-category totals use the trip's single currency, else EUR excluding non-converted expenses (mirror `SpesaRepository` SQL).
- Version bump on functional change: `pubspec.yaml` and `lib/version.dart` kept in sync.
- New code lives under `lib/services/export/`; tests under `test/export/`.

---

### Task 1: TrasfertaReport model + builder

Pure aggregation/sorting shared by both renderers. No new dependencies.

**Files:**
- Create: `lib/services/export/trasferta_report.dart`
- Test: `test/export/trasferta_report_test.dart`

**Interfaces:**
- Consumes: `Spesa` (`lib/data/models/spesa.dart`: `id`, `data`, `categoria`, `fornitore`, `importo`, `valuta`, `importoEur`, `tassoCambio`, `note`, `createdAt`), `Trasferta` (`valutaDefault`, `nome`, `luogo`, `dataInizio`, `dataFine`), `Categoria` (`lib/core/constants/categories.dart`: `.label`).
- Produces:
  - `class ReportRow { final int? spesaId; final DateTime data; final Categoria categoria; final String? fornitore; final double importo; final String valuta; final double? importoEur; final double? tassoCambio; final String? note; }`
  - `class TrasfertaReport { final Trasferta trasferta; final List<ReportRow> righe; final Map<String,double> totaliPerValuta; final double totaleEur; final int countSenzaEur; final Map<Categoria,double> totaliPerCategoria; final String valutaCategorie; static TrasfertaReport build(Trasferta trasferta, List<Spesa> spese); }`

- [ ] **Step 1: Write the failing test**

Create `test/export/trasferta_report_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip({String valuta = 'JPY'}) => Trasferta(
      id: 1,
      nome: 'Tokyo',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      dataFine: DateTime(2026, 7, 5),
      valutaDefault: valuta,
      createdAt: DateTime(2026, 7, 1),
    );

Spesa _spesa({
  int? id,
  DateTime? data,
  Categoria categoria = Categoria.pranzo,
  double importo = 1000,
  String valuta = 'JPY',
  double? importoEur,
  DateTime? createdAt,
}) =>
    Spesa(
      id: id,
      trasfertaId: 1,
      data: data ?? DateTime(2026, 7, 2),
      categoria: categoria,
      importo: importo,
      valuta: valuta,
      importoEur: importoEur,
      createdAt: createdAt ?? DateTime(2026, 7, 2, 12),
    );

void main() {
  test('righe sorted by data then createdAt', () {
    final r = TrasfertaReport.build(_trip(), [
      _spesa(id: 1, data: DateTime(2026, 7, 3), createdAt: DateTime(2026, 7, 3, 9)),
      _spesa(id: 2, data: DateTime(2026, 7, 2), createdAt: DateTime(2026, 7, 2, 15)),
      _spesa(id: 3, data: DateTime(2026, 7, 2), createdAt: DateTime(2026, 7, 2, 8)),
    ]);
    expect(r.righe.map((e) => e.spesaId).toList(), [3, 2, 1]);
  });

  test('totaliPerValuta puts trip currency first then descending amount', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(valuta: 'USD', importo: 50),
      _spesa(valuta: 'JPY', importo: 1000),
      _spesa(valuta: 'EUR', importo: 200),
    ]);
    expect(r.totaliPerValuta.keys.first, 'JPY');
    // EUR (200) before USD (50) among the non-trip currencies.
    expect(r.totaliPerValuta.keys.toList(), ['JPY', 'EUR', 'USD']);
  });

  test('totaleEur sums non-null, countSenzaEur counts nulls', () {
    final r = TrasfertaReport.build(_trip(), [
      _spesa(importoEur: 6.5),
      _spesa(importoEur: 3.5),
      _spesa(importoEur: null),
    ]);
    expect(r.totaleEur, closeTo(10.0, 1e-9));
    expect(r.countSenzaEur, 1);
  });

  test('single-currency trip: category totals in original currency', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(categoria: Categoria.pranzo, importo: 1000, valuta: 'JPY', importoEur: 6),
      _spesa(categoria: Categoria.pranzo, importo: 500, valuta: 'JPY', importoEur: 3),
      _spesa(categoria: Categoria.taxi, importo: 800, valuta: 'JPY', importoEur: 5),
    ]);
    expect(r.valutaCategorie, 'JPY');
    expect(r.totaliPerCategoria[Categoria.pranzo], 1500);
    expect(r.totaliPerCategoria[Categoria.taxi], 800);
  });

  test('multi-currency trip: category totals in EUR excluding non-converted', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(categoria: Categoria.pranzo, importo: 1000, valuta: 'JPY', importoEur: 6),
      _spesa(categoria: Categoria.pranzo, importo: 10, valuta: 'USD', importoEur: null),
      _spesa(categoria: Categoria.taxi, importo: 20, valuta: 'USD', importoEur: 18),
    ]);
    expect(r.valutaCategorie, 'EUR');
    // The JPY pranzo (6 EUR) counts; the USD pranzo (no EUR) is excluded.
    expect(r.totaliPerCategoria[Categoria.pranzo], closeTo(6, 1e-9));
    expect(r.totaliPerCategoria[Categoria.taxi], closeTo(18, 1e-9));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/export/trasferta_report_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../trasferta_report.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/export/trasferta_report.dart`:

```dart
import '../../core/constants/categories.dart';
import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';

/// One expense as it appears in an export (a flattened [Spesa]).
class ReportRow {
  const ReportRow({
    required this.spesaId,
    required this.data,
    required this.categoria,
    this.fornitore,
    required this.importo,
    required this.valuta,
    this.importoEur,
    this.tassoCambio,
    this.note,
  });

  final int? spesaId;
  final DateTime data;
  final Categoria categoria;
  final String? fornitore;
  final double importo;
  final String valuta;
  final double? importoEur;
  final double? tassoCambio;
  final String? note;
}

/// Pure aggregation of a trip's expenses for CSV/PDF export. Mirrors the
/// aggregation rules of [SpesaRepository] (per-currency totals, EUR total,
/// per-category totals) so an export matches the in-app screens exactly.
class TrasfertaReport {
  const TrasfertaReport({
    required this.trasferta,
    required this.righe,
    required this.totaliPerValuta,
    required this.totaleEur,
    required this.countSenzaEur,
    required this.totaliPerCategoria,
    required this.valutaCategorie,
  });

  final Trasferta trasferta;
  final List<ReportRow> righe;

  /// Sum of `importo` per currency; trip currency first, then descending.
  final Map<String, double> totaliPerValuta;
  final double totaleEur;
  final int countSenzaEur;
  final Map<Categoria, double> totaliPerCategoria;

  /// Currency [totaliPerCategoria] is expressed in: the trip's single
  /// currency, or 'EUR' when the trip mixes currencies.
  final String valutaCategorie;

  static TrasfertaReport build(Trasferta trasferta, List<Spesa> spese) {
    final righe = [...spese]..sort((a, b) {
        final byData = a.data.compareTo(b.data);
        return byData != 0 ? byData : a.createdAt.compareTo(b.createdAt);
      });

    final perValuta = <String, double>{};
    for (final s in spese) {
      perValuta[s.valuta] = (perValuta[s.valuta] ?? 0) + s.importo;
    }
    final valutaTrasferta = trasferta.valutaDefault;
    final valuteOrdinate = perValuta.entries.toList()
      ..sort((a, b) {
        if (a.key == valutaTrasferta) return -1;
        if (b.key == valutaTrasferta) return 1;
        return b.value.compareTo(a.value);
      });
    final totaliPerValuta = {for (final e in valuteOrdinate) e.key: e.value};

    final totaleEur = spese
        .where((s) => s.importoEur != null)
        .fold<double>(0, (sum, s) => sum + s.importoEur!);
    final countSenzaEur = spese.where((s) => s.importoEur == null).length;

    final valutaUnica =
        perValuta.length == 1 ? perValuta.keys.first : null;
    final valutaCategorie = valutaUnica ?? 'EUR';
    final totaliPerCategoria = <Categoria, double>{};
    for (final s in spese) {
      if (valutaUnica == null) {
        // Multi-currency: sum EUR, silently excluding non-converted spese
        // (same rule as SpesaRepository.totaliEurPerCategoria).
        if (s.importoEur == null) continue;
        totaliPerCategoria[s.categoria] =
            (totaliPerCategoria[s.categoria] ?? 0) + s.importoEur!;
      } else {
        totaliPerCategoria[s.categoria] =
            (totaliPerCategoria[s.categoria] ?? 0) + s.importo;
      }
    }

    return TrasfertaReport(
      trasferta: trasferta,
      righe: [
        for (final s in righe)
          ReportRow(
            spesaId: s.id,
            data: s.data,
            categoria: s.categoria,
            fornitore: s.fornitore,
            importo: s.importo,
            valuta: s.valuta,
            importoEur: s.importoEur,
            tassoCambio: s.tassoCambio,
            note: s.note,
          ),
      ],
      totaliPerValuta: totaliPerValuta,
      totaleEur: totaleEur,
      countSenzaEur: countSenzaEur,
      totaliPerCategoria: totaliPerCategoria,
      valutaCategorie: valutaCategorie,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/export/trasferta_report_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/export/trasferta_report.dart test/export/trasferta_report_test.dart
git commit -m "feat: TrasfertaReport aggregation for CSV/PDF export"
```

---

### Task 2: CsvExportService

Renders a `TrasfertaReport` to a CSV string.

**Files:**
- Modify: `pubspec.yaml` (add `csv` dependency)
- Create: `lib/services/export/csv_export_service.dart`
- Test: `test/export/csv_export_service_test.dart`

**Interfaces:**
- Consumes: `TrasfertaReport`, `ReportRow` (Task 1); `formatDate` (`lib/core/utils/formatters.dart`); `Categoria.label`.
- Produces: `class CsvExportService { const CsvExportService(); String build(TrasfertaReport report); }`

- [ ] **Step 1: Add the `csv` dependency**

Run: `flutter pub add csv`
Expected: `pubspec.yaml` gains a `csv:` line under `dependencies`; `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

Create `test/export/csv_export_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/csv_export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip() => Trasferta(
      id: 1,
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  test('header row and BOM prefix', () {
    final csv = const CsvExportService().build(
      TrasfertaReport.build(_trip(), const []),
    );
    expect(csv.codeUnitAt(0), 0xFEFF); // BOM
    expect(csv,
        contains('Data;Categoria;Fornitore;Importo;Valuta;Importo EUR;Tasso;Note'));
  });

  test('formats date, comma decimals, empty cells for nulls', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 1289.5,
        valuta: 'JPY',
        importoEur: 8.4,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('02/07/2026;Pranzo;;1289,50;JPY;8,40;;'));
  });

  test('quotes a note containing the separator', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.cena,
        importo: 10,
        valuta: 'EUR',
        note: 'cena; con cliente',
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('"cena; con cliente"'));
  });

  test('total row omits the note when nothing is unconverted', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        importoEur: 10,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    // Total is the last row: ListToCsvConverter adds no trailing eol after it.
    expect(csv, contains('TOTALE EUR;;;;;10,00;;'));
  });

  test('total row notes excluded expenses when some are unconverted', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 1000,
        valuta: 'JPY',
        importoEur: null,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('TOTALE EUR;;;;;0,00;;esclude 1 spese non convertite'));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/export/csv_export_service_test.dart`
Expected: FAIL — `csv_export_service.dart` does not exist.

- [ ] **Step 4: Write minimal implementation**

Create `lib/services/export/csv_export_service.dart`:

```dart
import 'package:csv/csv.dart';

import '../../core/utils/formatters.dart';
import 'trasferta_report.dart';

/// Renders a [TrasfertaReport] to an Excel-IT-friendly CSV: `;` separator,
/// comma decimals, UTF-8 BOM so accents/€ show correctly on open.
class CsvExportService {
  const CsvExportService();

  static const _bom = '﻿';

  String build(TrasfertaReport report) {
    final rows = <List<String>>[
      const [
        'Data',
        'Categoria',
        'Fornitore',
        'Importo',
        'Valuta',
        'Importo EUR',
        'Tasso',
        'Note',
      ],
      for (final r in report.righe)
        [
          formatDate(r.data),
          r.categoria.label,
          r.fornitore ?? '',
          _money(r.importo),
          r.valuta,
          r.importoEur == null ? '' : _money(r.importoEur!),
          r.tassoCambio == null ? '' : _rate(r.tassoCambio!),
          r.note ?? '',
        ],
      const <String>[],
      [
        'TOTALE EUR',
        '', '', '', '',
        _money(report.totaleEur),
        '',
        report.countSenzaEur > 0
            ? 'esclude ${report.countSenzaEur} spese non convertite'
            : '',
      ],
    ];
    final body = const ListToCsvConverter(fieldDelimiter: ';', eol: '\r\n')
        .convert(rows);
    return '$_bom$body';
  }

  /// Money as text with a comma decimal, two digits, no thousands separator
  /// (the `;` separator means the comma is safe and Excel-IT reads it as a
  /// number).
  String _money(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  /// Exchange rate keeps its stored precision (rates can be < 0.01).
  String _rate(double value) => value.toString().replaceAll('.', ',');
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/export/csv_export_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/export/csv_export_service.dart test/export/csv_export_service_test.dart
git commit -m "feat: CSV export renderer"
```

---

### Task 3: PdfExportService + fonts

Renders a `TrasfertaReport` (+ photo bytes) to PDF bytes. Adds the `pdf`
dependency and bundles Noto fonts as assets.

**Files:**
- Modify: `pubspec.yaml` (add `pdf` dependency; add `assets/fonts/` to assets)
- Create (download): `assets/fonts/NotoSans-Regular.ttf`, `assets/fonts/NotoSans-Bold.ttf`, `assets/fonts/NotoSansJP-Regular.ttf`
- Create: `lib/services/export/pdf_export_service.dart`
- Test: `test/export/pdf_export_service_test.dart`

**Interfaces:**
- Consumes: `TrasfertaReport`, `ReportRow` (Task 1); `formatDate`, `formatValuta`, `formatEur`, `formatDateRange` (`lib/core/utils/formatters.dart`); `Categoria.label`.
- Produces:
  - `class PdfFonts { const PdfFonts({required pw.Font regular, required pw.Font bold, required pw.Font jp}); static Future<PdfFonts> load(); }`
  - `class PdfExportService { const PdfExportService(); Future<Uint8List> build(TrasfertaReport report, {required Map<int,Uint8List> fotoBytesBySpesaId, required PdfFonts fonts}); }`

- [ ] **Step 1: Add the `pdf` dependency**

Run: `flutter pub add pdf`
Expected: `pubspec.yaml` gains a `pdf:` line; `flutter pub get` succeeds. (Do NOT add `printing`.)

- [ ] **Step 2: Download the font assets**

The `pdf` package embeds **TrueType** fonts only (glyf outlines; OTF/CFF is not
supported). Noto Sans JP must be the TrueType variable file, not the `.otf`.

```bash
mkdir -p assets/fonts
# Latin base (static TTF, hinted)
curl -L -o assets/fonts/NotoSans-Regular.ttf \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf"
curl -L -o assets/fonts/NotoSans-Bold.ttf \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Bold.ttf"
# Japanese fallback (variable TrueType from google/fonts)
curl -L -o assets/fonts/NotoSansJP-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
```

Verify each file is a real font, not an HTML 404 page:

```bash
ls -l assets/fonts
file assets/fonts/*.ttf   # expect "TrueType Font data" for all three
```

Expected: three `.ttf` files; Latin ~0.3–0.6 MB each, JP ~4–6 MB; `file` reports TrueType.
If a URL 404s, obtain the equivalent static/variable **TTF** from https://fonts.google.com (Noto Sans, Noto Sans JP) and place it at the same path. Do not substitute an `.otf`.

- [ ] **Step 3: Register the fonts as assets**

In `pubspec.yaml`, under `flutter:` → `assets:`, add the fonts directory
alongside the existing entries. It must stay in release builds (unlike the
`[OCR-HARNESS]` assets), so place it as its own entry:

```yaml
  assets:
    # PDF export fonts (Noto Sans + Noto Sans JP) — KEEP in release builds.
    - assets/fonts/
    # [OCR-HARNESS] Asset usati SOLO da integration_test/mlkit_ocr_accuracy_test.dart
    # (misura accuratezza ML Kit on-device sulle foto reali). ~2 MB: rimuovere
    # queste righe prima di una build di release.
    - scontrini_training/
    - test/fixtures/real_receipts/jp/
```

Run: `flutter pub get`
Expected: success.

- [ ] **Step 4: Write the failing smoke test**

Create `test/export/pdf_export_service_test.dart`:

```dart
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
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `flutter test test/export/pdf_export_service_test.dart`
Expected: FAIL — `pdf_export_service.dart` does not exist.

- [ ] **Step 6: Write minimal implementation**

Create `lib/services/export/pdf_export_service.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import 'trasferta_report.dart';

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
        if (report.totaleEur > 0) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            '≈ ${formatEur(report.totaleEur)}'
            '${report.countSenzaEur > 0 ? ' (esclude ${report.countSenzaEur} spese non convertite)' : ''}',
            style: const pw.TextStyle(fontSize: 11),
          ),
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
      pw.TableRow(children: [
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
    final didascalia = [
      formatDate(r.data),
      if (r.fornitore != null && r.fornitore!.isNotEmpty)
        r.fornitore
      else
        r.categoria.label,
      formatValuta(r.importo, r.valuta),
      r.categoria.label,
    ].join(' · ');
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
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/export/pdf_export_service_test.dart`
Expected: PASS (3 tests). If it fails loading a font, re-check Step 2 (the JP file must be TrueType, not OTF).

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock assets/fonts lib/services/export/pdf_export_service.dart test/export/pdf_export_service_test.dart
git commit -m "feat: PDF export renderer with Noto fonts"
```

---

### Task 4: ExportService + filename + controller photo bytes

Ties the renderers to a temp file + share, and lets the controller hand over
the receipt photo bytes.

**Files:**
- Create: `lib/services/export/export_file_name.dart`
- Create: `lib/services/export/export_service.dart`
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart` (add `fotoBytesBySpesa`)
- Test: `test/export/export_service_test.dart`
- Test: `test/trasferta_detail_controller_test.dart` (add a case for `fotoBytesBySpesa`)

**Interfaces:**
- Consumes: `TrasfertaReport` (Task 1), `CsvExportService` (Task 2), `PdfExportService` + `PdfFonts` (Task 3), `Trasferta`, `share_plus` (`SharePlus.instance.share(ShareParams(files: ...))`), `path_provider` (`getTemporaryDirectory`), `path` (`p.join`).
- Produces:
  - `String exportFileName(Trasferta t, String ext)` — e.g. `NotaSpese_Tokyo_2026-07.csv`.
  - `class ExportService { ExportService({PdfExportService pdf, CsvExportService csv, Future<Directory> Function()? tempDir, Future<void> Function(List<XFile>)? share, Future<PdfFonts> Function()? loadFonts}); Future<void> exportCsv(TrasfertaReport report, Trasferta trasferta); Future<void> exportPdf(TrasfertaReport report, Trasferta trasferta, Map<int,Uint8List> fotoBytesBySpesaId); }`
  - `TrasfertaDetailController.fotoBytesBySpesa() → Future<Map<int,Uint8List>>` (spesa id → full-size jpg bytes; unreadable photos skipped).

- [ ] **Step 1: Write the failing test for filename + CSV delivery**

Create `test/export/export_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/export_file_name.dart';
import 'package:nota_spese/services/export/export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart'; // re-exports XFile

Trasferta _trip({String nome = 'Tokyo 2026'}) => Trasferta(
      id: 1,
      nome: nome,
      dataInizio: DateTime(2026, 7, 1),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  group('exportFileName', () {
    test('slugs the trip name and uses dataInizio year-month', () {
      expect(exportFileName(_trip(nome: 'Tokyo 2026'), 'csv'),
          'NotaSpese_Tokyo_2026_2026-07.csv');
    });

    test('strips unsafe characters and falls back when empty', () {
      expect(exportFileName(_trip(nome: 'Roma/Milano!'), 'pdf'),
          'NotaSpese_RomaMilano_2026-07.pdf');
      expect(exportFileName(_trip(nome: '***'), 'pdf'),
          'NotaSpese_trasferta_2026-07.pdf');
    });
  });

  test('exportCsv writes a BOM file to temp and shares it', () async {
    final dir = await Directory.systemTemp.createTemp('export_test');
    final shared = <XFile>[];
    final service = ExportService(
      tempDir: () async => dir,
      share: (files) async => shared.addAll(files),
    );
    final report = TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        importoEur: 10,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]);

    await service.exportCsv(report, _trip());

    expect(shared, hasLength(1));
    expect(p.basename(shared.first.path), 'NotaSpese_Tokyo_2026_2026-07.csv');
    final content = await File(shared.first.path).readAsString();
    expect(content.codeUnitAt(0), 0xFEFF);
    expect(content, contains('TOTALE EUR'));

    await dir.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/export/export_service_test.dart`
Expected: FAIL — `export_file_name.dart` / `export_service.dart` do not exist.

- [ ] **Step 3: Write the filename helper**

Create `lib/services/export/export_file_name.dart`:

```dart
import '../../data/models/trasferta.dart';

/// Share filename: `NotaSpese_<slug>_<yyyy-MM>.<ext>`. The slug is the trip
/// name with whitespace collapsed to `_` and unsafe characters removed;
/// `yyyy-MM` comes from `dataInizio`.
String exportFileName(Trasferta t, String ext) {
  final slug = t.nome
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
  final safe = slug.isEmpty ? 'trasferta' : slug;
  final ym = '${t.dataInizio.year.toString().padLeft(4, '0')}-'
      '${t.dataInizio.month.toString().padLeft(2, '0')}';
  return 'NotaSpese_${safe}_$ym.$ext';
}
```

- [ ] **Step 4: Write the ExportService**

Create `lib/services/export/export_service.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/trasferta.dart';
import 'csv_export_service.dart';
import 'export_file_name.dart';
import 'pdf_export_service.dart';
import 'trasferta_report.dart';

/// Turns a [TrasfertaReport] into a shared file. Renderers, temp dir, share
/// and font loading are injected so the whole flow is host-testable; the
/// defaults are the real Android implementations.
class ExportService {
  ExportService({
    PdfExportService pdf = const PdfExportService(),
    CsvExportService csv = const CsvExportService(),
    Future<Directory> Function()? tempDir,
    Future<void> Function(List<XFile>)? share,
    Future<PdfFonts> Function()? loadFonts,
  })  : _pdf = pdf,
        _csv = csv,
        _tempDir = tempDir ?? getTemporaryDirectory,
        _share = share ??
            ((files) => SharePlus.instance.share(ShareParams(files: files))),
        _loadFonts = loadFonts ?? PdfFonts.load;

  final PdfExportService _pdf;
  final CsvExportService _csv;
  final Future<Directory> Function() _tempDir;
  final Future<void> Function(List<XFile>) _share;
  final Future<PdfFonts> Function() _loadFonts;

  Future<void> exportCsv(TrasfertaReport report, Trasferta trasferta) async {
    final content = _csv.build(report);
    final file = await _tempFile(exportFileName(trasferta, 'csv'));
    await file.writeAsString(content);
    await _share([XFile(file.path)]);
  }

  Future<void> exportPdf(TrasfertaReport report, Trasferta trasferta,
      Map<int, Uint8List> fotoBytesBySpesaId) async {
    final fonts = await _loadFonts();
    final bytes = await _pdf.build(report,
        fotoBytesBySpesaId: fotoBytesBySpesaId, fonts: fonts);
    final file = await _tempFile(exportFileName(trasferta, 'pdf'));
    await file.writeAsBytes(bytes);
    await _share([XFile(file.path)]);
  }

  Future<File> _tempFile(String name) async =>
      File(p.join((await _tempDir()).path, name));
}
```

- [ ] **Step 5: Run the export service test**

Run: `flutter test test/export/export_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Write the failing controller test**

In `test/trasferta_detail_controller_test.dart`, add a test that a created
spesa with a photo yields its bytes from `fotoBytesBySpesa()`. Reuse the
existing harness in that file (`controller()`, `writeSourceImage()`,
`trasfertaId`, `spesaRepo`). Add near the other `createSpesa` tests:

```dart
  test('fotoBytesBySpesa returns bytes keyed by spesa id', () async {
    final c = controller();
    await c.load();
    final source = await writeSourceImage();
    await c.createSpesa(
      Spesa(
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        createdAt: DateTime(2026, 7, 2),
      ),
      fotoSourcePath: source,
    );
    final spesaId = c.fotoBySpesa.keys.single;

    final bytes = await c.fotoBytesBySpesa();

    expect(bytes.keys, contains(spesaId));
    expect(bytes[spesaId], isNotEmpty);
    c.dispose();
  });
```

(If `writeSourceImage`/`Categoria` are not already imported in that file, add
the imports the surrounding tests use.)

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/trasferta_detail_controller_test.dart`
Expected: FAIL — `fotoBytesBySpesa` is not defined on the controller.

- [ ] **Step 8: Implement `fotoBytesBySpesa` on the controller**

In `lib/ui/trasferte/trasferta_detail_controller.dart`, add these imports at
the top with the others:

```dart
import 'dart:io';
import 'dart:typed_data';
```

Then add this method (e.g. after `absolutePhotoPath`):

```dart
  /// Full-size receipt photo bytes keyed by spesa id, for PDF export.
  /// Best-effort: a spesa whose photo file is missing/unreadable is skipped.
  Future<Map<int, Uint8List>> fotoBytesBySpesa() async {
    final result = <int, Uint8List>{};
    for (final entry in fotoBySpesa.entries) {
      try {
        final abs = await _photoService.absolutePath(entry.value.filePath);
        result[entry.key] = await File(abs).readAsBytes();
      } catch (_) {
        // Skip: the PDF simply omits this receipt's photo page.
      }
    }
    return result;
  }
```

- [ ] **Step 9: Run the controller test again**

Run: `flutter test test/trasferta_detail_controller_test.dart`
Expected: PASS (all, including the new test).

- [ ] **Step 10: Commit**

```bash
git add lib/services/export/export_file_name.dart lib/services/export/export_service.dart lib/ui/trasferte/trasferta_detail_controller.dart test/export/export_service_test.dart test/trasferta_detail_controller_test.dart
git commit -m "feat: export delivery service and controller photo bytes"
```

---

### Task 5: Menu wiring + version bump

Two menu voices in the detail app bar trigger the export; guard the empty
trip; show a progress/error SnackBar.

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart`
- Modify: `pubspec.yaml` (version → `0.10.0+15`)
- Modify: `lib/version.dart` (`appVersion` → `0.10.0`)
- Test: `test/trasferta_detail_screen_test.dart` (add export cases)

**Interfaces:**
- Consumes: `ExportService`, `exportFileName`, `TrasfertaReport` (Task 4); `controller.trasferta`, `controller.speseByData`, `controller.fotoBytesBySpesa()` (Task 4).
- Produces: two `PopupMenuItem`s keyed `Key('detail-export-pdf')` / `Key('detail-export-csv')`; an optional `ExportService? exportService` screen param (defaults to a real `ExportService()`), injectable by tests.

- [ ] **Step 1: Write the failing widget test**

In `test/trasferta_detail_screen_test.dart`, add a fake export service and two
tests. Add this fake near the other fakes at the top:

```dart
class _FakeExportService extends ExportService {
  _FakeExportService() : super(share: ((_) async {}));
  final List<String> calls = [];
  @override
  Future<void> exportCsv(report, trasferta) async => calls.add('csv');
  @override
  Future<void> exportPdf(report, trasferta, fotoBytes) async =>
      calls.add('pdf');
}
```

Add the import:

```dart
import 'package:nota_spese/services/export/export_service.dart';
```

Extend the `pump` helper so it forwards an optional export service to the
screen (add a parameter `ExportService? exportService` and pass
`exportService: exportService` to `TrasfertaDetailScreen(...)`).

Then add the tests (a trip with one spesa is already seeded by the file's
helpers — follow the existing seeding pattern used by other tests in this
file):

```dart
  testWidgets('CSV menu voice triggers the CSV export', (tester) async {
    final export = _FakeExportService();
    // Seed one spesa for trasfertaId using the file's existing helpers,
    // then:
    await pump(tester, exportService: export);
    await tester.tap(find.byType(PopupMenuButton<DetailAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-export-csv')));
    await tester.pumpAndSettle();
    expect(export.calls, ['csv']);
  });

  testWidgets('export with no spese shows a SnackBar and does not export',
      (tester) async {
    final export = _FakeExportService();
    await pump(tester, exportService: export); // empty trip
    await tester.tap(find.byType(PopupMenuButton<DetailAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-export-pdf')));
    await tester.pumpAndSettle();
    expect(export.calls, isEmpty);
    expect(find.text('Nessuna spesa da esportare'), findsOneWidget);
  });
```

(Match the seeding to how the existing tests in this file create a spesa for
`trasfertaId`; the first test needs one spesa, the second needs none.)

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/trasferta_detail_screen_test.dart`
Expected: FAIL — `exportService` param and the two menu keys do not exist.

- [ ] **Step 3: Add the export param and menu voices**

In `lib/ui/trasferte/trasferta_detail_screen.dart`:

Add the import:

```dart
import '../../services/export/export_service.dart';
import '../../services/export/trasferta_report.dart';
```

Extend the `DetailAction` enum:

```dart
enum DetailAction { modifica, archivia, ripristina, elimina, esportaPdf, esportaCsv }
```

Add the optional field + constructor param (near `cropService`):

```dart
    this.exportService,
```
```dart
  final ExportService? exportService;
```

In the state, resolve it once:

```dart
  late final ExportService _exportService =
      widget.exportService ?? ExportService();
```

In `_onAction`, add the two cases (calls the helper below):

```dart
      case DetailAction.esportaPdf:
        await _esporta(pdf: true);
      case DetailAction.esportaCsv:
        await _esporta(pdf: false);
```

Add the two menu items to the `itemBuilder` list (after `elimina`):

```dart
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      key: Key('detail-export-pdf'),
                      value: DetailAction.esportaPdf,
                      child: Text('Esporta PDF')),
                  const PopupMenuItem(
                      key: Key('detail-export-csv'),
                      value: DetailAction.esportaCsv,
                      child: Text('Esporta CSV')),
```

Add the export helper method:

```dart
  Future<void> _esporta({required bool pdf}) async {
    final t = controller.trasferta;
    if (t == null) return;
    final spese = [for (final l in controller.speseByData.values) ...l];
    if (spese.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuna spesa da esportare')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Generazione in corso…'),
        duration: Duration(seconds: 30)));
    try {
      final report = TrasfertaReport.build(t, spese);
      if (pdf) {
        final fotoBytes = await controller.fotoBytesBySpesa();
        await _exportService.exportPdf(report, t, fotoBytes);
      } else {
        await _exportService.exportCsv(report, t);
      }
      messenger.hideCurrentSnackBar();
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
          content: Text('Esportazione non riuscita')));
    }
  }
```

- [ ] **Step 4: Run the widget test**

Run: `flutter test test/trasferta_detail_screen_test.dart`
Expected: PASS (all, including the two new tests).

- [ ] **Step 5: Bump the version**

In `pubspec.yaml`: `version: 0.10.0+15`.
In `lib/version.dart`: `const String appVersion = '0.10.0';`.

- [ ] **Step 6: Full verification**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (the whole suite, not only the export tests).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/trasferte/trasferta_detail_screen.dart pubspec.yaml lib/version.dart test/trasferta_detail_screen_test.dart
git commit -m "feat: PDF/CSV export menu voices in trip detail"
```

---

## Verification checklist (project CLAUDE.md)

- [ ] `flutter analyze` → zero issues (Task 5, Step 6).
- [ ] APK build/emulator: **skip explicitly** — Android emulator not available on this machine; export UI is exercised by the widget test, renderers by unit/smoke tests on host. Real share-sheet + on-device PDF open must be verified manually on a physical device when one is connected.
- [ ] New logic covered by tests: report aggregation, CSV, PDF smoke, export delivery, controller photo bytes, menu wiring.
- [ ] `ToDo.md` updated: tick the Fase 7 export items.

## Notes / gotchas

- The `pdf` package embeds TrueType only. If the smoke test throws on font
  load, the JP file is probably an OTF — replace with the variable TrueType.
- `MultiPage` breaks the expense `pw.Table` at row boundaries; the header is
  not auto-repeated on continuation pages (accepted for v1).
- `assets/fonts/` must stay in release builds — keep it separate from the
  `[OCR-HARNESS]` asset lines slated for removal before release.
```
