# Fase 1 — Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Data layer completo di NotaSpese: enum Categoria/valute, modelli Trasferta/Spesa/Foto, DbHelper SQLite, tre repository con delete cascade esplicito, unit test verdi con `sqflite_common_ffi`.

**Architecture:** Repository pattern sopra `sqflite`; DDL da `Specifiche.md` §Modello Dati. FK enforce via `PRAGMA foreign_keys = ON` in `onConfigure`. Delete cascade esplicito in transazione (file fisici PRIMA dei record). Nessuna DI: costruttori ricevono dipendenze.

**Tech Stack:** Flutter/Dart, `sqflite` (prod), `sqflite_common_ffi` (test in-memory), `path`, `material_symbols_icons`.

## Global Constraints

- Progetto: `nota_spese`, Android only, `minSdk 33`, `compileSdk 35`.
- Naming: `snake_case.dart`; identificatori inglese, nomi dominio da spec in italiano (`Trasferta`, `Spesa`, `Foto`, `Categoria`, tabelle `trasferte`/`spese`/`foto`).
- Date su DB: TEXT ISO 8601 — `'yyyy-MM-dd'` per date, ISO completo per `created_at`.
- Importi: `REAL`, sempre valuta originale; `importo_eur` NULL se non convertito.
- Valute: enum nel codice, **no HRK**; frequenti: EUR, USD, JPY, GBP, CHF, RSD, AED, SGD.
- Categorie: `pranzo · cena · colazione · trasporto · taxi · hotel · parcheggio · carburante · telefono · altro`.
- Mai `sqflite`/filesystem dai controller: solo repository/service (vale dalle fasi UI, il data layer è l'unico a toccare il DB).
- **NIENTE commit automatici** (CLAUDE.md globale > skill): commit SOLO su richiesta esplicita dell'utente, a fine fase.
- Bump versione a fine fase: `pubspec.yaml` → `0.2.0+2`, `lib/version.dart` → `'0.2.0'`.
- Verifica finale fase: `flutter analyze` zero issue + `flutter test` verde.

---

### Task 1: Enum Categoria + valute (core/constants)

**Files:**
- Create: `lib/core/constants/categories.dart`
- Create: `lib/core/constants/currencies.dart`
- Test: `test/constants_test.dart`
- Delete: `lib/core/constants/.gitkeep`

**Interfaces:**
- Produces: `enum Categoria { pranzo, cena, ... }` con `label` (String IT), `icon` (IconData); `enum Currency { eur, usd, ... }` con `code` (ISO 4217), `nome` (String IT), `symbol`, `decimalDigits` (int), `frequente` (bool), `static List<Currency> get frequenti`, `static Currency? fromCode(String code)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/constants_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/core/constants/currencies.dart';

void main() {
  group('Categoria', () {
    test('has the 10 categories from the spec', () {
      expect(Categoria.values.map((c) => c.name), [
        'pranzo', 'cena', 'colazione', 'trasporto', 'taxi',
        'hotel', 'parcheggio', 'carburante', 'telefono', 'altro',
      ]);
    });

    test('every category has a non-empty label and an icon', () {
      for (final c in Categoria.values) {
        expect(c.label, isNotEmpty);
        expect(c.icon, isNotNull);
      }
    });

    test('round-trips through name for DB storage', () {
      expect(Categoria.values.byName('taxi'), Categoria.taxi);
    });
  });

  group('Currency', () {
    test('does not include HRK (kuna replaced by EUR in 2023)', () {
      expect(Currency.values.where((c) => c.code == 'HRK'), isEmpty);
    });

    test('frequent currencies are the 8 from the spec, EUR first', () {
      expect(Currency.frequenti.map((c) => c.code), [
        'EUR', 'USD', 'JPY', 'GBP', 'CHF', 'RSD', 'AED', 'SGD',
      ]);
    });

    test('fromCode resolves known codes and returns null for unknown', () {
      expect(Currency.fromCode('JPY'), Currency.jpy);
      expect(Currency.fromCode('XXX'), isNull);
    });

    test('JPY has zero decimal digits', () {
      expect(Currency.jpy.decimalDigits, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/constants_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'nota_spese/core/constants/categories.dart'` (file inesistente).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/constants/categories.dart
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Expense categories (spec: Specifiche.md §Modello Dati).
/// Stored in DB as TEXT via [name]; read back with Categoria.values.byName.
enum Categoria {
  pranzo('Pranzo', Symbols.lunch_dining),
  cena('Cena', Symbols.dinner_dining),
  colazione('Colazione', Symbols.bakery_dining),
  trasporto('Trasporto', Symbols.commute),
  taxi('Taxi', Symbols.local_taxi),
  hotel('Hotel', Symbols.hotel),
  parcheggio('Parcheggio', Symbols.local_parking),
  carburante('Carburante', Symbols.local_gas_station),
  telefono('Telefono', Symbols.call),
  altro('Altro', Symbols.category);

  const Categoria(this.label, this.icon);

  /// UI label (Italian, per project convention).
  final String label;
  final IconData icon;
}
```

```dart
// lib/core/constants/currencies.dart
/// Supported currencies (ISO 4217). Static list, no external API.
/// No HRK: Croatian kuna replaced by EUR in 2023.
enum Currency {
  // Frequent (shown on top of the picker, spec §8) — EUR first.
  eur('EUR', 'Euro', '€', 2, frequente: true),
  usd('USD', 'Dollaro USA', r'$', 2, frequente: true),
  jpy('JPY', 'Yen giapponese', '¥', 0, frequente: true),
  gbp('GBP', 'Sterlina britannica', '£', 2, frequente: true),
  chf('CHF', 'Franco svizzero', 'CHF', 2, frequente: true),
  rsd('RSD', 'Dinaro serbo', 'дин.', 2, frequente: true),
  aed('AED', 'Dirham EAU', 'د.إ', 2, frequente: true),
  sgd('SGD', 'Dollaro di Singapore', r'S$', 2, frequente: true),
  // Others (alphabetical by code).
  all('ALL', 'Lek albanese', 'L', 2),
  aud('AUD', 'Dollaro australiano', r'A$', 2),
  bam('BAM', 'Marco bosniaco', 'KM', 2),
  bgn('BGN', 'Lev bulgaro', 'лв', 2),
  brl('BRL', 'Real brasiliano', r'R$', 2),
  cad('CAD', 'Dollaro canadese', r'C$', 2),
  cny('CNY', 'Yuan cinese', '¥', 2),
  czk('CZK', 'Corona ceca', 'Kč', 2),
  dkk('DKK', 'Corona danese', 'kr', 2),
  hkd('HKD', 'Dollaro di Hong Kong', r'HK$', 2),
  huf('HUF', 'Fiorino ungherese', 'Ft', 2),
  idr('IDR', 'Rupia indonesiana', 'Rp', 2),
  ils('ILS', 'Nuovo shekel israeliano', '₪', 2),
  inr('INR', 'Rupia indiana', '₹', 2),
  krw('KRW', 'Won sudcoreano', '₩', 0),
  kwd('KWD', 'Dinaro kuwaitiano', 'د.ك', 3),
  mkd('MKD', 'Denar macedone', 'ден', 2),
  mxn('MXN', 'Peso messicano', r'MX$', 2),
  myr('MYR', 'Ringgit malese', 'RM', 2),
  nok('NOK', 'Corona norvegese', 'kr', 2),
  nzd('NZD', 'Dollaro neozelandese', r'NZ$', 2),
  php('PHP', 'Peso filippino', '₱', 2),
  pln('PLN', 'Złoty polacco', 'zł', 2),
  qar('QAR', 'Riyal del Qatar', 'ر.ق', 2),
  ron('RON', 'Leu romeno', 'lei', 2),
  sar('SAR', 'Riyal saudita', 'ر.س', 2),
  sek('SEK', 'Corona svedese', 'kr', 2),
  thb('THB', 'Baht thailandese', '฿', 2),
  try_('TRY', 'Lira turca', '₺', 2),
  twd('TWD', 'Nuovo dollaro taiwanese', r'NT$', 2),
  vnd('VND', 'Dong vietnamita', '₫', 0),
  zar('ZAR', 'Rand sudafricano', 'R', 2);

  const Currency(this.code, this.nome, this.symbol, this.decimalDigits,
      {this.frequente = false});

  /// ISO 4217 code, stored as-is in DB column `spese.valuta`.
  final String code;
  final String nome;
  final String symbol;
  final int decimalDigits;
  final bool frequente;

  /// Frequent currencies for the top of the picker, spec order.
  static List<Currency> get frequenti =>
      values.where((c) => c.frequente).toList();

  static Currency? fromCode(String code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
```

Note: `try` è keyword Dart → valore enum `try_` con `code: 'TRY'` (per questo il DB salva `code`, mai `name`).

- [ ] **Step 4: Delete `lib/core/constants/.gitkeep`** (la cartella ora ha contenuto reale).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/constants_test.dart`
Expected: PASS (tutti i test verdi).

---

### Task 2: Modelli Trasferta, Spesa, Foto

**Files:**
- Create: `lib/data/models/trasferta.dart`
- Create: `lib/data/models/spesa.dart`
- Create: `lib/data/models/foto.dart`
- Test: `test/models_test.dart`
- Delete: `lib/data/models/.gitkeep`

**Interfaces:**
- Consumes: `Categoria` (Task 1).
- Produces:
  - `Trasferta({int? id, required String nome, String? luogo, required DateTime dataInizio, DateTime? dataFine, String valutaDefault = 'EUR', String? linguaDefault, bool archiviata = false, String? note, required DateTime createdAt})` + `toMap()` / `factory Trasferta.fromMap(Map<String, Object?> map)`
  - `Spesa({int? id, required int trasfertaId, required DateTime data, required Categoria categoria, String? fornitore, required double importo, required String valuta, double? importoEur, double? tassoCambio, String? note, String? ocrEngine, required DateTime createdAt})` + `toMap()` / `fromMap`
  - `Foto({int? id, required int spesaId, required String filePath, required String thumbPath, required DateTime createdAt})` + `toMap()` / `fromMap`
- Convenzioni map: chiavi = nomi colonna DDL (`data_inizio`, `trasferta_id`, …); date → `'yyyy-MM-dd'`; `created_at` → ISO completo; `archiviata` → 0/1; `categoria` → `categoria.name`; `valuta` → String ISO (non enum: resiliente a codici futuri).

- [ ] **Step 1: Write the failing test**

```dart
// test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/foto.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';

void main() {
  group('Trasferta', () {
    final trasferta = Trasferta(
      id: 1,
      nome: 'Tokyo Q3',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      dataFine: DateTime(2026, 7, 15),
      valutaDefault: 'JPY',
      linguaDefault: 'ja',
      archiviata: false,
      note: 'fiera',
      createdAt: DateTime(2026, 7, 9, 18, 30),
    );

    test('toMap uses DDL column names and ISO dates', () {
      final map = trasferta.toMap();
      expect(map['nome'], 'Tokyo Q3');
      expect(map['data_inizio'], '2026-07-10');
      expect(map['data_fine'], '2026-07-15');
      expect(map['valuta_default'], 'JPY');
      expect(map['lingua_default'], 'ja');
      expect(map['archiviata'], 0);
      expect(map['created_at'], DateTime(2026, 7, 9, 18, 30).toIso8601String());
    });

    test('fromMap(toMap) round-trips', () {
      final back = Trasferta.fromMap(trasferta.toMap());
      expect(back.id, trasferta.id);
      expect(back.nome, trasferta.nome);
      expect(back.dataInizio, trasferta.dataInizio);
      expect(back.dataFine, trasferta.dataFine);
      expect(back.archiviata, trasferta.archiviata);
      expect(back.createdAt, trasferta.createdAt);
    });

    test('handles NULL data_fine (trip in progress) and archiviata=1', () {
      final t = Trasferta.fromMap({
        'id': 2,
        'nome': 'Milano',
        'luogo': null,
        'data_inizio': '2026-07-01',
        'data_fine': null,
        'valuta_default': 'EUR',
        'lingua_default': null,
        'archiviata': 1,
        'note': null,
        'created_at': '2026-07-01T08:00:00.000',
      });
      expect(t.dataFine, isNull);
      expect(t.archiviata, isTrue);
    });
  });

  group('Spesa', () {
    final spesa = Spesa(
      id: 5,
      trasfertaId: 1,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      fornitore: 'Ichiran',
      importo: 3200,
      valuta: 'JPY',
      importoEur: 19.5,
      tassoCambio: 0.0061,
      note: null,
      ocrEngine: 'mlkit',
      createdAt: DateTime(2026, 7, 11, 21, 5),
    );

    test('toMap stores categoria.name and DDL column names', () {
      final map = spesa.toMap();
      expect(map['trasferta_id'], 1);
      expect(map['data'], '2026-07-11');
      expect(map['categoria'], 'cena');
      expect(map['importo'], 3200);
      expect(map['valuta'], 'JPY');
      expect(map['importo_eur'], 19.5);
      expect(map['ocr_engine'], 'mlkit');
    });

    test('fromMap(toMap) round-trips including enum', () {
      final back = Spesa.fromMap(spesa.toMap());
      expect(back.categoria, Categoria.cena);
      expect(back.importo, 3200);
      expect(back.importoEur, 19.5);
      expect(back.data, DateTime(2026, 7, 11));
    });

    test('manual entry: importo_eur, tasso_cambio, ocr_engine all null', () {
      final s = Spesa.fromMap({
        'id': 6,
        'trasferta_id': 1,
        'data': '2026-07-12',
        'categoria': 'taxi',
        'fornitore': null,
        'importo': 12.0,
        'valuta': 'EUR',
        'importo_eur': null,
        'tasso_cambio': null,
        'note': null,
        'ocr_engine': null,
        'created_at': '2026-07-12T10:00:00.000',
      });
      expect(s.importoEur, isNull);
      expect(s.ocrEngine, isNull);
      expect(s.categoria, Categoria.taxi);
    });
  });

  group('Foto', () {
    test('round-trips with relative paths', () {
      final foto = Foto(
        id: 3,
        spesaId: 5,
        filePath: 'receipts/5.jpg',
        thumbPath: 'thumbnails/5.jpg',
        createdAt: DateTime(2026, 7, 11, 21, 6),
      );
      final back = Foto.fromMap(foto.toMap());
      expect(back.spesaId, 5);
      expect(back.filePath, 'receipts/5.jpg');
      expect(back.thumbPath, 'thumbnails/5.jpg');
      expect(back.createdAt, foto.createdAt);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models_test.dart`
Expected: FAIL — package imports non risolti.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/models/trasferta.dart

/// Trip model, mirrors table `trasferte` (Specifiche.md DDL).
class Trasferta {
  const Trasferta({
    this.id,
    required this.nome,
    this.luogo,
    required this.dataInizio,
    this.dataFine,
    this.valutaDefault = 'EUR',
    this.linguaDefault,
    this.archiviata = false,
    this.note,
    required this.createdAt,
  });

  factory Trasferta.fromMap(Map<String, Object?> map) => Trasferta(
        id: map['id'] as int?,
        nome: map['nome'] as String,
        luogo: map['luogo'] as String?,
        dataInizio: DateTime.parse(map['data_inizio'] as String),
        dataFine: map['data_fine'] == null
            ? null
            : DateTime.parse(map['data_fine'] as String),
        valutaDefault: map['valuta_default'] as String,
        linguaDefault: map['lingua_default'] as String?,
        archiviata: (map['archiviata'] as int) != 0,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final String nome;
  final String? luogo;
  final DateTime dataInizio;
  final DateTime? dataFine; // NULL = in corso
  final String valutaDefault; // ISO 4217
  final String? linguaDefault; // it|en|ja|sr|de, NULL = auto
  final bool archiviata;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'nome': nome,
        'luogo': luogo,
        'data_inizio': _isoDate(dataInizio),
        'data_fine': dataFine == null ? null : _isoDate(dataFine!),
        'valuta_default': valutaDefault,
        'lingua_default': linguaDefault,
        'archiviata': archiviata ? 1 : 0,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
```

```dart
// lib/data/models/spesa.dart
import '../../core/constants/categories.dart';

/// Expense model, mirrors table `spese` (Specifiche.md DDL).
/// `valuta` stays a raw ISO string (not the enum) so unknown codes never crash a read.
class Spesa {
  const Spesa({
    this.id,
    required this.trasfertaId,
    required this.data,
    required this.categoria,
    this.fornitore,
    required this.importo,
    required this.valuta,
    this.importoEur,
    this.tassoCambio,
    this.note,
    this.ocrEngine,
    required this.createdAt,
  });

  factory Spesa.fromMap(Map<String, Object?> map) => Spesa(
        id: map['id'] as int?,
        trasfertaId: map['trasferta_id'] as int,
        data: DateTime.parse(map['data'] as String),
        categoria: Categoria.values.byName(map['categoria'] as String),
        fornitore: map['fornitore'] as String?,
        importo: (map['importo'] as num).toDouble(),
        valuta: map['valuta'] as String,
        importoEur: (map['importo_eur'] as num?)?.toDouble(),
        tassoCambio: (map['tasso_cambio'] as num?)?.toDouble(),
        note: map['note'] as String?,
        ocrEngine: map['ocr_engine'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final int trasfertaId;
  final DateTime data;
  final Categoria categoria;
  final String? fornitore;
  final double importo; // sempre valuta originale
  final String valuta; // ISO 4217
  final double? importoEur; // NULL se non convertito
  final double? tassoCambio; // NULL se inserito a mano
  final String? note;
  final String? ocrEngine; // 'mlkit'|'local_ai'|'claude'|NULL (manuale)
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'trasferta_id': trasfertaId,
        'data': _isoDate(data),
        'categoria': categoria.name,
        'fornitore': fornitore,
        'importo': importo,
        'valuta': valuta,
        'importo_eur': importoEur,
        'tasso_cambio': tassoCambio,
        'note': note,
        'ocr_engine': ocrEngine,
        'created_at': createdAt.toIso8601String(),
      };
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
```

```dart
// lib/data/models/foto.dart

/// Photo model, mirrors table `foto` (1:1 with spesa via UNIQUE spesa_id).
/// Paths are RELATIVE to the configured photo directory (Specifiche.md §2).
class Foto {
  const Foto({
    this.id,
    required this.spesaId,
    required this.filePath,
    required this.thumbPath,
    required this.createdAt,
  });

  factory Foto.fromMap(Map<String, Object?> map) => Foto(
        id: map['id'] as int?,
        spesaId: map['spesa_id'] as int,
        filePath: map['file_path'] as String,
        thumbPath: map['thumb_path'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final int spesaId;
  final String filePath;
  final String thumbPath;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'spesa_id': spesaId,
        'file_path': filePath,
        'thumb_path': thumbPath,
        'created_at': createdAt.toIso8601String(),
      };
}
```

- [ ] **Step 4: Delete `lib/data/models/.gitkeep`**

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models_test.dart`
Expected: PASS.

---

### Task 3: DbHelper (schema, PRAGMA FK, versione DB)

**Files:**
- Create: `lib/data/db/db_helper.dart`
- Modify: `pubspec.yaml` (aggiungere `path` come dipendenza diretta)
- Test: `test/db_helper_test.dart`
- Delete: `lib/data/db/.gitkeep`

**Interfaces:**
- Produces: `DbHelper({DatabaseFactory? factory, String? path})`; `Future<Database> get database`; `Future<void> close()`; `static const int dbVersion = 1`; `static const String dbFileName = 'nota_spese.db'`. In produzione si costruisce `DbHelper()` (default sqflite); nei test `DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath)`.

- [ ] **Step 1: Add `path` dependency**

Run: `flutter pub add path`
Expected: `path` aggiunto a `dependencies` in `pubspec.yaml` (serve per `join()`; è già transitiva di sqflite ma il lint `depend_on_referenced_packages` richiede la dipendenza diretta).

- [ ] **Step 2: Write the failing test**

```dart
// test/db_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;

  setUp(() {
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => dbHelper.close());

  test('creates schema with the three tables and indexes', () async {
    final db = await dbHelper.database;
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = tables.map((r) => r['name']).toSet();
    expect(names.containsAll(['trasferte', 'spese', 'foto']), isTrue);

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'");
    final indexNames = indexes.map((r) => r['name']).toSet();
    expect(indexNames.containsAll(['idx_spese_trasferta', 'idx_spese_data']),
        isTrue);
  });

  test('foreign keys are ON for the connection', () async {
    final db = await dbHelper.database;
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first.values.first, 1);
  });

  test('rejects spesa referencing a missing trasferta', () async {
    final db = await dbHelper.database;
    expect(
      () => db.insert('spese', {
        'trasferta_id': 999,
        'data': '2026-07-17',
        'categoria': 'altro',
        'importo': 1.0,
        'valuta': 'EUR',
        'created_at': '2026-07-17T10:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('enforces UNIQUE(spesa_id) on foto (1:1)', () async {
    final db = await dbHelper.database;
    final tId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-17',
      'valuta_default': 'EUR',
      'archiviata': 0,
      'created_at': '2026-07-17T10:00:00.000',
    });
    final sId = await db.insert('spese', {
      'trasferta_id': tId,
      'data': '2026-07-17',
      'categoria': 'altro',
      'importo': 1.0,
      'valuta': 'EUR',
      'created_at': '2026-07-17T10:00:00.000',
    });
    Map<String, Object?> fotoRow() => {
          'spesa_id': sId,
          'file_path': 'receipts/x.jpg',
          'thumb_path': 'thumbnails/x.jpg',
          'created_at': '2026-07-17T10:00:00.000',
        };
    await db.insert('foto', fotoRow());
    expect(() => db.insert('foto', fotoRow()),
        throwsA(isA<DatabaseException>()));
  });

  test('database version is 1', () async {
    final db = await dbHelper.database;
    expect(await db.getVersion(), DbHelper.dbVersion);
    expect(DbHelper.dbVersion, 1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/db_helper_test.dart`
Expected: FAIL — `db_helper.dart` inesistente.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/data/db/db_helper.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Opens nota_spese.db, enforces PRAGMA foreign_keys=ON on every
/// connection (Specifiche.md §5) and owns schema creation/versioning.
/// Production: DbHelper(). Tests: DbHelper(factory: databaseFactoryFfi,
/// path: inMemoryDatabasePath).
class DbHelper {
  DbHelper({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  /// Bump on any schema change (formal migrations deferred to v1.1).
  static const int dbVersion = 1;
  static const String dbFileName = 'nota_spese.db';

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _db;

  Future<Database> get database async {
    final cached = _db;
    if (cached != null && cached.isOpen) return cached;
    final factory = _factory ?? databaseFactory;
    final path = _path ?? join(await factory.getDatabasesPath(), dbFileName);
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE trasferte (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  nome           TEXT NOT NULL,
  luogo          TEXT,
  data_inizio    TEXT NOT NULL,
  data_fine      TEXT,
  valuta_default TEXT NOT NULL DEFAULT 'EUR',
  lingua_default TEXT,
  archiviata     INTEGER NOT NULL DEFAULT 0,
  note           TEXT,
  created_at     TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE spese (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  trasferta_id INTEGER NOT NULL REFERENCES trasferte(id),
  data         TEXT NOT NULL,
  categoria    TEXT NOT NULL,
  fornitore    TEXT,
  importo      REAL NOT NULL,
  valuta       TEXT NOT NULL,
  importo_eur  REAL,
  tasso_cambio REAL,
  note         TEXT,
  ocr_engine   TEXT,
  created_at   TEXT NOT NULL
)''');
    await db.execute('CREATE INDEX idx_spese_trasferta ON spese(trasferta_id)');
    await db.execute('CREATE INDEX idx_spese_data ON spese(data)');
    await db.execute('''
CREATE TABLE foto (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  spesa_id   INTEGER NOT NULL UNIQUE REFERENCES spese(id),
  file_path  TEXT NOT NULL,
  thumb_path TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
  }
}
```

- [ ] **Step 5: Delete `lib/data/db/.gitkeep`**

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/db_helper_test.dart`
Expected: PASS (5 test).

---

### Task 4: FotoRepository (record + file fisici)

**Files:**
- Create: `lib/data/repositories/foto_repository.dart`
- Test: `test/repositories_test.dart` (nuovo file, gruppo `FotoRepository`)
- Delete: `lib/data/repositories/.gitkeep`

**Interfaces:**
- Consumes: `DbHelper` (Task 3), `Foto` (Task 2).
- Produces: `FotoRepository(DbHelper dbHelper, {required Future<String> Function() basePathProvider})`; `Future<int> insert(Foto foto)`; `Future<Foto?> getBySpesa(int spesaId)`; `Future<void> deleteBySpesa(int spesaId)` (file fisici PRIMA del record); `Future<void> deleteFiles(List<Foto> fotos)` (solo file, usata dalle cascade di Task 5/6).
- `basePathProvider` restituisce la directory foto assoluta; i path nel DB sono relativi. In produzione verrà cablata in fase 4 (`getApplicationDocumentsDirectory()`); nei test → temp dir.

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/foto.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late Directory tempDir;

  setUp(() {
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('nota_spese_test');
  });

  tearDown(() async {
    await dbHelper.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Inserts a minimal trasferta + spesa, returns the spesa id.
  Future<int> insertSpesaFixture() async {
    final db = await dbHelper.database;
    final tId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-17',
      'valuta_default': 'EUR',
      'archiviata': 0,
      'created_at': '2026-07-17T10:00:00.000',
    });
    return db.insert('spese', {
      'trasferta_id': tId,
      'data': '2026-07-17',
      'categoria': 'altro',
      'importo': 1.0,
      'valuta': 'EUR',
      'created_at': '2026-07-17T10:00:00.000',
    });
  }

  /// Creates fake photo + thumbnail files under tempDir, returns the Foto.
  Foto createFotoFixture(int spesaId) {
    final rel = 'receipts/$spesaId.jpg';
    final thumbRel = 'thumbnails/$spesaId.jpg';
    File(p.join(tempDir.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync('jpg');
    File(p.join(tempDir.path, thumbRel))
      ..createSync(recursive: true)
      ..writeAsStringSync('thumb');
    return Foto(
      spesaId: spesaId,
      filePath: rel,
      thumbPath: thumbRel,
      createdAt: DateTime(2026, 7, 17, 10),
    );
  }

  group('FotoRepository', () {
    late FotoRepository repo;

    setUp(() {
      repo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
    });

    test('insert + getBySpesa round-trip', () async {
      final spesaId = await insertSpesaFixture();
      final id = await repo.insert(createFotoFixture(spesaId));
      expect(id, isPositive);
      final loaded = await repo.getBySpesa(spesaId);
      expect(loaded, isNotNull);
      expect(loaded!.filePath, 'receipts/$spesaId.jpg');
    });

    test('getBySpesa returns null when no photo', () async {
      final spesaId = await insertSpesaFixture();
      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa removes physical files AND record', () async {
      final spesaId = await insertSpesaFixture();
      final foto = createFotoFixture(spesaId);
      await repo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));
      final thumb = File(p.join(tempDir.path, foto.thumbPath));
      expect(file.existsSync(), isTrue);

      await repo.deleteBySpesa(spesaId);

      expect(file.existsSync(), isFalse);
      expect(thumb.existsSync(), isFalse);
      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa tolerates already-missing files', () async {
      final spesaId = await insertSpesaFixture();
      final foto = createFotoFixture(spesaId);
      await repo.insert(foto);
      File(p.join(tempDir.path, foto.filePath)).deleteSync();

      await repo.deleteBySpesa(spesaId); // must not throw

      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa with no photo is a no-op', () async {
      final spesaId = await insertSpesaFixture();
      await repo.deleteBySpesa(spesaId); // must not throw
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories_test.dart`
Expected: FAIL — `foto_repository.dart` inesistente.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/repositories/foto_repository.dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/db_helper.dart';
import '../models/foto.dart';

/// Photo records + physical files. Deletion order is files FIRST,
/// then DB record (Specifiche.md §2): a dangling file is recoverable,
/// a dangling record pointing to nothing is a bug.
class FotoRepository {
  FotoRepository(this._dbHelper, {required this.basePathProvider});

  final DbHelper _dbHelper;

  /// Absolute photo directory; DB paths are relative to it.
  final Future<String> Function() basePathProvider;

  Future<int> insert(Foto foto) async {
    final db = await _dbHelper.database;
    return db.insert('foto', foto.toMap());
  }

  Future<Foto?> getBySpesa(int spesaId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('foto',
        where: 'spesa_id = ?', whereArgs: [spesaId], limit: 1);
    return rows.isEmpty ? null : Foto.fromMap(rows.first);
  }

  /// Deletes physical files first, then the record.
  Future<void> deleteBySpesa(int spesaId) async {
    final foto = await getBySpesa(spesaId);
    if (foto == null) return;
    await deleteFiles([foto]);
    final db = await _dbHelper.database;
    await db.delete('foto', where: 'spesa_id = ?', whereArgs: [spesaId]);
  }

  /// Deletes photo + thumbnail files only (records untouched).
  /// Missing files are ignored: deletion must never block on them.
  Future<void> deleteFiles(List<Foto> fotos) async {
    final base = await basePathProvider();
    for (final foto in fotos) {
      for (final rel in [foto.filePath, foto.thumbPath]) {
        final file = File(p.join(base, rel));
        if (file.existsSync()) await file.delete();
      }
    }
  }
}
```

- [ ] **Step 4: Delete `lib/data/repositories/.gitkeep`**

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/repositories_test.dart`
Expected: PASS (5 test FotoRepository).

---

### Task 5: SpesaRepository (CRUD, raggruppamento, totali)

**Files:**
- Create: `lib/data/repositories/spesa_repository.dart`
- Test: `test/repositories_test.dart` (aggiungere gruppo `SpesaRepository`)

**Interfaces:**
- Consumes: `DbHelper`, `Spesa`, `Categoria`, `FotoRepository.deleteFiles` / `getBySpesa` (Task 4).
- Produces: `SpesaRepository(DbHelper dbHelper, FotoRepository fotoRepository)`;
  - `Future<int> insert(Spesa spesa)`
  - `Future<void> update(Spesa spesa)` (richiede `id` non null)
  - `Future<Spesa?> getById(int id)`
  - `Future<void> delete(int id)` — file foto → record foto + record spesa in transazione
  - `Future<List<Spesa>> getByTrasferta(int trasfertaId)` — ORDER BY `data DESC, id DESC`
  - `Future<Map<DateTime, List<Spesa>>> getByTrasfertaGroupedByData(int trasfertaId)` — chiavi in ordine data DESC
  - `Future<Map<String, double>> totaliPerValuta(int trasfertaId)` — somma `importo` per `valuta`
  - `Future<double> totaleEur(int trasfertaId)` — somma `importo_eur` non-NULL, 0 se nessuno
  - `Future<int> countSenzaEur(int trasfertaId)` — spese con `importo_eur` NULL (per UI "escluse dal totale EUR")
  - `Future<Map<Categoria, double>> totaliEurPerCategoria(int trasfertaId)` — solo spese con `importo_eur` non-NULL

- [ ] **Step 1: Write the failing test** — aggiungere a `test/repositories_test.dart` (import `spesa_repository.dart`, `spesa.dart`, `categories.dart`):

```dart
  group('SpesaRepository', () {
    late FotoRepository fotoRepo;
    late SpesaRepository repo;
    late int trasfertaId;

    Spesa spesa({
      DateTime? data,
      Categoria categoria = Categoria.altro,
      double importo = 10,
      String valuta = 'EUR',
      double? importoEur,
    }) =>
        Spesa(
          trasfertaId: trasfertaId,
          data: data ?? DateTime(2026, 7, 17),
          categoria: categoria,
          importo: importo,
          valuta: valuta,
          importoEur: importoEur,
          createdAt: DateTime(2026, 7, 17, 10),
        );

    setUp(() async {
      fotoRepo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
      repo = SpesaRepository(dbHelper, fotoRepo);
      final db = await dbHelper.database;
      trasfertaId = await db.insert('trasferte', {
        'nome': 'T',
        'data_inizio': '2026-07-15',
        'valuta_default': 'EUR',
        'archiviata': 0,
        'created_at': '2026-07-15T08:00:00.000',
      });
    });

    test('insert + getById round-trip', () async {
      final id = await repo.insert(spesa(importo: 42.5, valuta: 'JPY'));
      final loaded = await repo.getById(id);
      expect(loaded!.importo, 42.5);
      expect(loaded.valuta, 'JPY');
      expect(loaded.trasfertaId, trasfertaId);
    });

    test('update persists changes', () async {
      final id = await repo.insert(spesa());
      final loaded = await repo.getById(id);
      await repo.update(Spesa(
        id: id,
        trasfertaId: loaded!.trasfertaId,
        data: loaded.data,
        categoria: Categoria.hotel,
        importo: 99,
        valuta: 'EUR',
        createdAt: loaded.createdAt,
      ));
      final updated = await repo.getById(id);
      expect(updated!.categoria, Categoria.hotel);
      expect(updated.importo, 99);
    });

    test('delete removes spesa, its foto record and files', () async {
      final id = await repo.insert(spesa());
      final foto = createFotoFixture(id);
      await fotoRepo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));

      await repo.delete(id);

      expect(await repo.getById(id), isNull);
      expect(await fotoRepo.getBySpesa(id), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('getByTrasfertaGroupedByData groups by date, newest first', () async {
      await repo.insert(spesa(data: DateTime(2026, 7, 15)));
      await repo.insert(spesa(data: DateTime(2026, 7, 16)));
      await repo.insert(spesa(data: DateTime(2026, 7, 16)));

      final grouped = await repo.getByTrasfertaGroupedByData(trasfertaId);

      expect(grouped.keys.toList(),
          [DateTime(2026, 7, 16), DateTime(2026, 7, 15)]);
      expect(grouped[DateTime(2026, 7, 16)]!.length, 2);
    });

    test('totaliPerValuta sums importo grouped by currency', () async {
      await repo.insert(spesa(importo: 10, valuta: 'EUR'));
      await repo.insert(spesa(importo: 5.5, valuta: 'EUR'));
      await repo.insert(spesa(importo: 3000, valuta: 'JPY'));

      final totali = await repo.totaliPerValuta(trasfertaId);

      expect(totali, {'EUR': 15.5, 'JPY': 3000.0});
    });

    test('totaleEur sums only converted spese, countSenzaEur the rest',
        () async {
      await repo.insert(spesa(importoEur: 10));
      await repo.insert(spesa(importoEur: 20.5));
      await repo.insert(spesa(valuta: 'JPY')); // not converted

      expect(await repo.totaleEur(trasfertaId), 30.5);
      expect(await repo.countSenzaEur(trasfertaId), 1);
    });

    test('totaleEur is 0 for empty trasferta', () async {
      expect(await repo.totaleEur(trasfertaId), 0);
    });

    test('totaliEurPerCategoria groups by category, skips unconverted',
        () async {
      await repo.insert(spesa(categoria: Categoria.cena, importoEur: 25));
      await repo.insert(spesa(categoria: Categoria.cena, importoEur: 15));
      await repo.insert(spesa(categoria: Categoria.taxi, importoEur: 12));
      await repo.insert(spesa(categoria: Categoria.taxi)); // no EUR

      final totali = await repo.totaliEurPerCategoria(trasfertaId);

      expect(totali, {Categoria.cena: 40.0, Categoria.taxi: 12.0});
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories_test.dart`
Expected: FAIL — `spesa_repository.dart` inesistente.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/repositories/spesa_repository.dart
import 'dart:collection';

import '../../core/constants/categories.dart';
import '../db/db_helper.dart';
import '../models/spesa.dart';
import 'foto_repository.dart';

/// Expense CRUD + per-trasferta aggregations. Deleting a spesa also
/// removes its photo: files first, then both records in one transaction.
class SpesaRepository {
  SpesaRepository(this._dbHelper, this._fotoRepository);

  final DbHelper _dbHelper;
  final FotoRepository _fotoRepository;

  Future<int> insert(Spesa spesa) async {
    final db = await _dbHelper.database;
    return db.insert('spese', spesa.toMap());
  }

  Future<void> update(Spesa spesa) async {
    final db = await _dbHelper.database;
    await db.update('spese', spesa.toMap(),
        where: 'id = ?', whereArgs: [spesa.id]);
  }

  Future<Spesa?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('spese', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Spesa.fromMap(rows.first);
  }

  /// Photo files first, then foto + spesa records in one transaction.
  Future<void> delete(int id) async {
    final foto = await _fotoRepository.getBySpesa(id);
    if (foto != null) await _fotoRepository.deleteFiles([foto]);
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('foto', where: 'spesa_id = ?', whereArgs: [id]);
      await txn.delete('spese', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Spesa>> getByTrasferta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('spese',
        where: 'trasferta_id = ?',
        whereArgs: [trasfertaId],
        orderBy: 'data DESC, id DESC');
    return rows.map(Spesa.fromMap).toList();
  }

  /// Keys ordered by date DESC (insertion order of the LinkedHashMap).
  Future<Map<DateTime, List<Spesa>>> getByTrasfertaGroupedByData(
      int trasfertaId) async {
    final spese = await getByTrasferta(trasfertaId);
    final grouped = LinkedHashMap<DateTime, List<Spesa>>();
    for (final spesa in spese) {
      grouped.putIfAbsent(spesa.data, () => []).add(spesa);
    }
    return grouped;
  }

  /// Sum of `importo` in original currency, grouped by `valuta`.
  Future<Map<String, double>> totaliPerValuta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT valuta, SUM(importo) AS totale FROM spese '
        'WHERE trasferta_id = ? GROUP BY valuta',
        [trasfertaId]);
    return {
      for (final row in rows)
        row['valuta'] as String: (row['totale'] as num).toDouble(),
    };
  }

  /// Sum of converted amounts; spese without importo_eur are excluded
  /// (callers surface them via [countSenzaEur]).
  Future<double> totaleEur(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT SUM(importo_eur) AS totale FROM spese WHERE trasferta_id = ?',
        [trasfertaId]);
    return (rows.first['totale'] as num?)?.toDouble() ?? 0;
  }

  Future<int> countSenzaEur(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM spese '
        'WHERE trasferta_id = ? AND importo_eur IS NULL',
        [trasfertaId]);
    return rows.first['n'] as int;
  }

  Future<Map<Categoria, double>> totaliEurPerCategoria(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT categoria, SUM(importo_eur) AS totale FROM spese '
        'WHERE trasferta_id = ? AND importo_eur IS NOT NULL '
        'GROUP BY categoria',
        [trasfertaId]);
    return {
      for (final row in rows)
        Categoria.values.byName(row['categoria'] as String):
            (row['totale'] as num).toDouble(),
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories_test.dart`
Expected: PASS (gruppi FotoRepository + SpesaRepository).

---

### Task 6: TrasfertaRepository (CRUD, archivia, delete cascade)

**Files:**
- Create: `lib/data/repositories/trasferta_repository.dart`
- Test: `test/repositories_test.dart` (aggiungere gruppo `TrasfertaRepository`)

**Interfaces:**
- Consumes: `DbHelper`, `Trasferta`, `Foto`, `FotoRepository.deleteFiles`.
- Produces: `TrasfertaRepository(DbHelper dbHelper, FotoRepository fotoRepository)`;
  - `Future<int> insert(Trasferta trasferta)`
  - `Future<void> update(Trasferta trasferta)`
  - `Future<Trasferta?> getById(int id)`
  - `Future<List<Trasferta>> getAttive()` — `archiviata = 0`, ORDER BY `data_inizio DESC`
  - `Future<List<Trasferta>> getArchiviate()` — `archiviata = 1`, ORDER BY `data_inizio DESC`
  - `Future<void> setArchiviata(int id, bool archiviata)` — archivia/ripristina
  - `Future<void> delete(int id)` — cascade esplicito: file foto → (transazione: record foto → spese → trasferta)

- [ ] **Step 1: Write the failing test** — aggiungere a `test/repositories_test.dart` (import `trasferta_repository.dart`, `trasferta.dart`):

```dart
  group('TrasfertaRepository', () {
    late FotoRepository fotoRepo;
    late TrasfertaRepository repo;

    Trasferta trasferta({
      String nome = 'Trip',
      DateTime? dataInizio,
      bool archiviata = false,
    }) =>
        Trasferta(
          nome: nome,
          dataInizio: dataInizio ?? DateTime(2026, 7, 15),
          archiviata: archiviata,
          createdAt: DateTime(2026, 7, 15, 8),
        );

    setUp(() {
      fotoRepo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
      repo = TrasfertaRepository(dbHelper, fotoRepo);
    });

    test('insert + getById round-trip with defaults', () async {
      final id = await repo.insert(trasferta(nome: 'Tokyo'));
      final loaded = await repo.getById(id);
      expect(loaded!.nome, 'Tokyo');
      expect(loaded.valutaDefault, 'EUR');
      expect(loaded.archiviata, isFalse);
    });

    test('update persists changes', () async {
      final id = await repo.insert(trasferta());
      final loaded = await repo.getById(id);
      await repo.update(Trasferta(
        id: id,
        nome: 'Renamed',
        dataInizio: loaded!.dataInizio,
        valutaDefault: 'JPY',
        createdAt: loaded.createdAt,
      ));
      final updated = await repo.getById(id);
      expect(updated!.nome, 'Renamed');
      expect(updated.valutaDefault, 'JPY');
    });

    test('getAttive/getArchiviate filter and order by data_inizio DESC',
        () async {
      await repo.insert(
          trasferta(nome: 'Old', dataInizio: DateTime(2026, 5, 1)));
      await repo.insert(
          trasferta(nome: 'New', dataInizio: DateTime(2026, 7, 1)));
      await repo.insert(trasferta(nome: 'Archived', archiviata: true));

      final attive = await repo.getAttive();
      expect(attive.map((t) => t.nome).toList(), ['New', 'Old']);

      final archiviate = await repo.getArchiviate();
      expect(archiviate.map((t) => t.nome).toList(), ['Archived']);
    });

    test('setArchiviata archives and restores', () async {
      final id = await repo.insert(trasferta());
      await repo.setArchiviata(id, true);
      expect((await repo.getById(id))!.archiviata, isTrue);
      await repo.setArchiviata(id, false);
      expect((await repo.getById(id))!.archiviata, isFalse);
    });

    test('delete cascades: photo files, foto, spese, trasferta', () async {
      final id = await repo.insert(trasferta());
      final db = await dbHelper.database;
      final spesaId = await db.insert('spese', {
        'trasferta_id': id,
        'data': '2026-07-16',
        'categoria': 'cena',
        'importo': 30.0,
        'valuta': 'EUR',
        'created_at': '2026-07-16T21:00:00.000',
      });
      final foto = createFotoFixture(spesaId);
      await fotoRepo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));
      final thumb = File(p.join(tempDir.path, foto.thumbPath));

      await repo.delete(id);

      expect(await repo.getById(id), isNull);
      expect(await db.query('spese'), isEmpty);
      expect(await db.query('foto'), isEmpty);
      expect(file.existsSync(), isFalse);
      expect(thumb.existsSync(), isFalse);
    });

    test('delete of trasferta without spese works', () async {
      final id = await repo.insert(trasferta());
      await repo.delete(id);
      expect(await repo.getById(id), isNull);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories_test.dart`
Expected: FAIL — `trasferta_repository.dart` inesistente.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/data/repositories/trasferta_repository.dart
import '../db/db_helper.dart';
import '../models/foto.dart';
import '../models/trasferta.dart';
import 'foto_repository.dart';

/// Trip CRUD + archive + explicit delete cascade (Specifiche.md §5):
/// photo files → foto records → spese → trasferta, records in one
/// SQLite transaction (files can't join it, so they go first).
class TrasfertaRepository {
  TrasfertaRepository(this._dbHelper, this._fotoRepository);

  final DbHelper _dbHelper;
  final FotoRepository _fotoRepository;

  Future<int> insert(Trasferta trasferta) async {
    final db = await _dbHelper.database;
    return db.insert('trasferte', trasferta.toMap());
  }

  Future<void> update(Trasferta trasferta) async {
    final db = await _dbHelper.database;
    await db.update('trasferte', trasferta.toMap(),
        where: 'id = ?', whereArgs: [trasferta.id]);
  }

  Future<Trasferta?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db
        .query('trasferte', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Trasferta.fromMap(rows.first);
  }

  Future<List<Trasferta>> getAttive() => _getByArchiviata(0);

  Future<List<Trasferta>> getArchiviate() => _getByArchiviata(1);

  Future<List<Trasferta>> _getByArchiviata(int archiviata) async {
    final db = await _dbHelper.database;
    final rows = await db.query('trasferte',
        where: 'archiviata = ?',
        whereArgs: [archiviata],
        orderBy: 'data_inizio DESC');
    return rows.map(Trasferta.fromMap).toList();
  }

  Future<void> setArchiviata(int id, bool archiviata) async {
    final db = await _dbHelper.database;
    await db.update('trasferte', {'archiviata': archiviata ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Explicit cascade; never relies on ON DELETE CASCADE.
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    final fotoRows = await db.rawQuery(
        'SELECT f.* FROM foto f '
        'JOIN spese s ON s.id = f.spesa_id '
        'WHERE s.trasferta_id = ?',
        [id]);
    await _fotoRepository.deleteFiles(fotoRows.map(Foto.fromMap).toList());
    await db.transaction((txn) async {
      await txn.delete('foto',
          where: 'spesa_id IN (SELECT id FROM spese WHERE trasferta_id = ?)',
          whereArgs: [id]);
      await txn.delete('spese', where: 'trasferta_id = ?', whereArgs: [id]);
      await txn.delete('trasferte', where: 'id = ?', whereArgs: [id]);
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories_test.dart`
Expected: PASS (tutti e tre i gruppi repository).

---

### Task 7: Verifica fase, bump versione, ToDo.md

**Files:**
- Modify: `pubspec.yaml:19` (`version: 0.1.0+1` → `version: 0.2.0+2`)
- Modify: `lib/version.dart` (`'0.1.0'` → `'0.2.0'`)
- Modify: `ToDo.md` (spuntare checkbox fase 1 + verifica fase 1)

**Interfaces:**
- Consumes: tutti i task precedenti completati.

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: PASS — tutti i test (constants, models, db_helper, repositories, widget_test).

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Bump version**

`pubspec.yaml`: `version: 0.2.0+2`
`lib/version.dart`: `const String appVersion = '0.2.0';`

- [ ] **Step 4: Update ToDo.md** — spuntare tutte le checkbox "Fase 1 — Data layer" e "Verifica fase 1" (test verdi + analyze zero issue), aggiungere data completamento `✅ 2026-07-17` accanto al titolo fase.

- [ ] **Step 5: Re-run `flutter analyze` + `flutter test`** (conferma post-bump)

Expected: entrambi verdi.

- [ ] **Step 6: STOP — niente commit automatico.** Riferire all'utente esito verifica; commit solo su sua richiesta esplicita.
