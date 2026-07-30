# Conversione EUR per tutte le valute — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertire in EUR le spese di *tutte* le valute (non solo le ~30 pubblicate dalla BCE) e mostrare nel riepilogo, per ogni valuta, quante spese e quanto è stato speso.

**Architecture:** `ExchangeService` passa da una a due fonti tassi in catena (BCE/frankfurter primaria, `@fawazahmed0/currency-api` come fallback per le 10 valute fuori BCE), con memorizzazione di sessione delle valute che la BCE non copre. Un nuovo tipo `ValutaBreakdown` porta conteggio + totale originale + totale EUR per valuta dal repository fino a header dettaglio, copertina PDF e sintesi CSV. Un `ConversionBackfillService` converte on-demand le spese salvate con `importo_eur` NULL.

**Tech Stack:** Flutter/Dart 3, `http` + `http/testing.MockClient`, `sqflite` (+ `sqflite_common_ffi` nei test), `pdf`, `csv`, `flutter_test`.

**Spec di riferimento:** `docs/superpowers/specs/2026-07-30-conversione-tutte-le-valute-design.md`

## Global Constraints

- Codice, identificatori, commenti e messaggi di commit in **inglese**; testi UI in **italiano**.
- **Nessuna modifica di schema DB.** `dbVersion` resta `1`. Le colonne `spese.importo_eur` e `spese.tasso_cambio` esistono già.
- `ExchangeService.convert()` **non deve mai lanciare** verso i chiamanti: qualunque fallimento → `null`. Il flusso di inserimento spesa non va mai bloccato.
- Nessun refactoring non richiesto: `totaliPerValuta`, `totaleEur`, `countSenzaEur` e `righeValuta` **restano** (la lista trasferte li usa ancora; migrarla è fuori scope).
- Ogni task termina con `flutter analyze` a **zero issue** e `flutter test` verde.
- Endpoint esatti, verificati con chiamate reali il 2026-07-30:
  - BCE: `https://api.frankfurter.dev/v1/<yyyy-MM-dd>?from=<CUR>&to=EUR` → `{"rates":{"EUR":<num>}}`
  - Fallback: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@<yyyy-MM-dd>/v1/currencies/<cur minuscolo>.json` → `{"<cur>":{"eur":<num>, ...}}`
  - `Uri.https` **non** codifica `@` nel path (verificato): l'URL esce letterale.
- Versione: `0.11.0+16` → `0.12.0+17`, bump una sola volta (Task 6).

---

### Task 1: Catena a due fonti in ExchangeService

**Files:**
- Modify: `lib/services/currency/exchange_service.dart:16-75`
- Test: `test/exchange_service_test.dart`

**Interfaces:**
- Consumes: niente (task iniziale).
- Produces: nessuna modifica alla firma pubblica. `ExchangeService.convert({required double amount, required String from, required DateTime date}) → Future<ExchangeResult?>` resta identica; cambia solo il comportamento interno.

- [ ] **Step 1: Write the failing tests**

Aggiungi in `test/exchange_service_test.dart`, dentro il `main()` esistente, dopo i test attuali. Nota: gli helper `ok(...)` e `service(...)` esistono già in cima al file e vanno riusati.

```dart
  // --- fase A: catena a due fonti (BCE → globale) ---

  http.Response globalOk(String cur, double rate) => http.Response(
      jsonEncode({
        'date': '2026-07-10',
        cur: {'usd': 1.0, 'eur': rate},
      }),
      200,
      headers: {'content-type': 'application/json'});

  test('ECB path uses api.frankfurter.dev with the /v1 prefix', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061);
    });
    await service(client)
        .convert(amount: 100, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(seen.host, 'api.frankfurter.dev');
    expect(seen.path, '/v1/2026-07-10');
    expect(seen.queryParameters, {'from': 'JPY', 'to': 'EUR'});
  });

  test('ECB 404 falls back to the global source and converts', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      if (request.url.host == 'api.frankfurter.dev') {
        return http.Response('not found', 404);
      }
      return globalOk('aed', 0.2345);
    });
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2026, 7, 10));
    expect(result!.rate, 0.2345);
    expect(result.amountEur, closeTo(23.45, 0.0001));
    expect(urls.last.host, 'cdn.jsdelivr.net');
    expect(urls.last.path,
        '/npm/@fawazahmed0/currency-api@2026-07-10/v1/currencies/aed.json');
  });

  test('ECB timeout falls back to the global source', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.frankfurter.dev') {
        throw const SocketException('offline');
      }
      return globalOk('rsd', 0.0085);
    });
    final result = await service(client)
        .convert(amount: 1000, from: 'RSD', date: DateTime(2026, 7, 10));
    expect(result!.rate, 0.0085);
  });

  test('both sources failing yields null, never throws', () async {
    final client = MockClient((request) async => http.Response('nope', 500));
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2026, 7, 10));
    expect(result, isNull);
  });

  test('a 404-ed currency skips ECB on the next call', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'api.frankfurter.dev') {
        return http.Response('not found', 404);
      }
      return globalOk('aed', 0.2345);
    });
    final s = service(client);
    await s.convert(amount: 1, from: 'AED', date: DateTime(2026, 7, 10));
    // Different day so the rate cache cannot serve it.
    await s.convert(amount: 1, from: 'AED', date: DateTime(2026, 7, 11));
    expect(hosts, [
      'api.frankfurter.dev',
      'cdn.jsdelivr.net',
      'cdn.jsdelivr.net',
    ]);
  });

  test('an ECB network failure is transient: next call retries ECB', () async {
    final hosts = <String>[];
    var ecbCalls = 0;
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'api.frankfurter.dev') {
        ecbCalls++;
        if (ecbCalls == 1) throw const SocketException('offline');
        return ok(0.0061);
      }
      return globalOk('jpy', 0.0060);
    });
    final s = service(client);
    await s.convert(amount: 1, from: 'JPY', date: DateTime(2026, 7, 10));
    final second = await s.convert(
        amount: 1, from: 'JPY', date: DateTime(2026, 7, 11));
    expect(second!.rate, 0.0061, reason: 'ECB must be retried, not skipped');
    expect(ecbCalls, 2);
  });

  test('global source 404 (date before its history) yields null', () async {
    final client = MockClient((request) async =>
        http.Response('not found', 404));
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2020, 1, 15));
    expect(result, isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```
flutter test test/exchange_service_test.dart
```

Atteso: FAIL. Il primo test fallisce su `seen.host` (`api.frankfurter.app` ≠ `api.frankfurter.dev`); quelli di fallback falliscono perché non esiste alcuna seconda richiesta e `convert` restituisce `null`.

- [ ] **Step 3: Implement the chain**

In `lib/services/currency/exchange_service.dart`, sostituisci il commento di classe e il metodo `_fetchRate`, e aggiungi i due fetch privati. Il resto della classe (`convert`, `_rateCache`, `_isoDay`) resta invariato.

Nuovo commento di classe (sostituisce le righe 16-20):

```dart
/// EUR conversion from two chained sources. ECB reference rates
/// (frankfurter) come first because they are the ones citable in an expense
/// claim; a community source covers the ~10 currencies the ECB does not
/// publish (RSD, AED, KWD, QAR, SAR, TWD, VND, ALL, BAM, MKD).
/// Never throws toward callers: ANY failure — toggle off, offline, timeout,
/// non-200, malformed JSON, unknown currency, date outside a source's
/// history — returns null so the expense flow is never blocked.
```

Aggiungi il campo accanto a `_rateCache`:

```dart
  /// Currencies frankfurter answered 404 for: outside the ECB set, a
  /// permanent fact, so later conversions skip straight to the fallback.
  /// Only 404 lands here — a network failure must stay retryable.
  final Set<String> _ecbUnsupported = {};
```

Sostituisci `_fetchRate` (righe 52-69) con:

```dart
  Future<double?> _fetchRate(String day, String from) async {
    if (!_ecbUnsupported.contains(from)) {
      final ecb = await _fetchEcbRate(day, from);
      if (ecb.rate != null) return ecb.rate;
      if (ecb.unsupported) _ecbUnsupported.add(from);
    }
    return _fetchGlobalRate(day, from);
  }

  /// ECB rates via frankfurter. `unsupported` is true only on HTTP 404
  /// (currency outside the ECB set); every other failure leaves it false so
  /// the caller retries this source next time.
  Future<({double? rate, bool unsupported})> _fetchEcbRate(
      String day, String from) async {
    const failed = (rate: null, unsupported: false);
    final uri = Uri.https(
        'api.frankfurter.dev', '/v1/$day', {'from': from, 'to': 'EUR'});
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode == 404) return (rate: null, unsupported: true);
      if (response.statusCode != 200) return failed;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return failed;
      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) return failed;
      final rate = rates['EUR'];
      return (rate: rate is num ? rate.toDouble() : null, unsupported: false);
    } on Exception {
      // TimeoutException, SocketException, ClientException, FormatException.
      return failed;
    }
  }

  /// Fallback source: daily historical files on a CDN, no API key. The rate
  /// is nested under the lowercased source currency, e.g. {"aed":{"eur":..}}.
  /// A 404 here means "no data for this day or currency" and is not cached:
  /// unlike the ECB set, it is not a permanent property of the currency.
  Future<double?> _fetchGlobalRate(String day, String from) async {
    final cur = from.toLowerCase();
    final uri = Uri.https('cdn.jsdelivr.net',
        '/npm/@fawazahmed0/currency-api@$day/v1/currencies/$cur.json');
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final rates = decoded[cur];
      if (rates is! Map<String, dynamic>) return null;
      final rate = rates['eur'];
      return rate is num ? rate.toDouble() : null;
    } on Exception {
      return null;
    }
  }
```

Verifica che in cima al file test ci sia `import 'dart:io';` (serve a `SocketException`): è già presente alla riga 2.

- [ ] **Step 4: Run the tests to verify they pass**

```
flutter test test/exchange_service_test.dart
flutter analyze
```

Atteso: tutti i test del file verdi (inclusi i preesistenti: EUR senza rete, toggle off, cache), `analyze` zero issue.

- [ ] **Step 5: Commit**

```bash
git add lib/services/currency/exchange_service.dart test/exchange_service_test.dart
git commit -m "feat: chain a fallback rate source for non-ECB currencies"
```

---

### Task 2: Modello ValutaBreakdown + ordinamento condiviso

**Files:**
- Create: `lib/data/models/valuta_breakdown.dart`
- Test: `test/valuta_breakdown_test.dart`

**Interfaces:**
- Consumes: niente.
- Produces:
  - `class ValutaBreakdown` con costruttore const nominale `({required String valuta, required int count, required double totale, required double totaleEur, required int countSenzaEur})` e gli stessi cinque campi finali pubblici.
  - `List<ValutaBreakdown> ordinaPerValuta(List<ValutaBreakdown> righe, String valutaTrasferta)` — non muta l'input.

- [ ] **Step 1: Write the failing test**

Crea `test/valuta_breakdown_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/models/valuta_breakdown.dart';

void main() {
  ValutaBreakdown row(String valuta, double totale) => ValutaBreakdown(
        valuta: valuta,
        count: 1,
        totale: totale,
        totaleEur: 0,
        countSenzaEur: 0,
      );

  test('trip currency comes first, others descending by amount', () {
    final righe = [row('AED', 50), row('JPY', 1000), row('USD', 300)];
    final ordered = ordinaPerValuta(righe, 'AED');
    expect(ordered.map((r) => r.valuta).toList(), ['AED', 'JPY', 'USD']);
  });

  test('without the trip currency, ordering is purely descending', () {
    final righe = [row('USD', 300), row('JPY', 1000)];
    final ordered = ordinaPerValuta(righe, 'EUR');
    expect(ordered.map((r) => r.valuta).toList(), ['JPY', 'USD']);
  });

  test('the input list is not mutated', () {
    final righe = [row('USD', 300), row('JPY', 1000)];
    ordinaPerValuta(righe, 'JPY');
    expect(righe.map((r) => r.valuta).toList(), ['USD', 'JPY']);
  });

  test('empty input yields an empty list', () {
    expect(ordinaPerValuta([], 'EUR'), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/valuta_breakdown_test.dart
```

Atteso: FAIL in compilazione — `Target of URI doesn't exist: 'package:nota_spese/data/models/valuta_breakdown.dart'`.

- [ ] **Step 3: Write the model**

Crea `lib/data/models/valuta_breakdown.dart`:

```dart
/// Per-currency slice of a trip: how many expenses were made in a currency,
/// how much they add up to in that currency, how much of that is converted
/// to EUR, and how many are still missing a conversion.
///
/// Not a DB entity: an aggregation of [Spesa] rows, shared by the detail
/// screen and the CSV/PDF exports so both show the same numbers.
class ValutaBreakdown {
  const ValutaBreakdown({
    required this.valuta,
    required this.count,
    required this.totale,
    required this.totaleEur,
    required this.countSenzaEur,
  });

  /// ISO 4217 code, raw as stored in `spese.valuta`.
  final String valuta;
  final int count;

  /// Sum of `importo`, in [valuta].
  final double totale;

  /// Sum of `importo_eur`; 0 when nothing in this currency is converted.
  final double totaleEur;

  /// Expenses in this currency still without `importo_eur`.
  final int countSenzaEur;
}

/// Trip currency first, then descending by original-currency total. Returns a
/// new list; the input is left untouched.
///
/// Same rule as [righeValuta] in `ui/shared/currency_rows.dart`, which still
/// serves the trip list's `Map<String, double>` totals.
List<ValutaBreakdown> ordinaPerValuta(
        List<ValutaBreakdown> righe, String valutaTrasferta) =>
    [...righe]..sort((a, b) {
        if (a.valuta == valutaTrasferta) return -1;
        if (b.valuta == valutaTrasferta) return 1;
        return b.totale.compareTo(a.totale);
      });
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/valuta_breakdown_test.dart
flutter analyze
```

Atteso: 4 test verdi, zero issue.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/valuta_breakdown.dart test/valuta_breakdown_test.dart
git commit -m "feat: add ValutaBreakdown aggregation model with shared ordering"
```

---

### Task 3: SpesaRepository.breakdownPerValuta

**Files:**
- Modify: `lib/data/repositories/spesa_repository.dart` (aggiunta dopo `totaliPerValuta`, riga 75)
- Test: `test/repositories_test.dart` (nel `group` di `SpesaRepository`, accanto agli altri test sui totali)

**Interfaces:**
- Consumes: `ValutaBreakdown` e `ordinaPerValuta` dal Task 2.
- Produces: `Future<List<ValutaBreakdown>> breakdownPerValuta(int trasfertaId, {required String valutaTrasferta})` — già ordinata.

- [ ] **Step 1: Write the failing test**

Aggiungi dentro il `group` di `SpesaRepository` in `test/repositories_test.dart` (l'helper locale `spesa({...})` e la variabile `trasfertaId` sono già definiti lì):

```dart
    test('breakdownPerValuta aggregates count, totals and missing EUR',
        () async {
      await repo.insert(spesa(importo: 1000, valuta: 'JPY', importoEur: 6.1));
      await repo.insert(spesa(importo: 2000, valuta: 'JPY', importoEur: 12.2));
      await repo.insert(spesa(importo: 50, valuta: 'AED'));
      final righe =
          await repo.breakdownPerValuta(trasfertaId, valutaTrasferta: 'JPY');

      expect(righe.map((r) => r.valuta).toList(), ['JPY', 'AED']);

      final jpy = righe.first;
      expect(jpy.count, 2);
      expect(jpy.totale, 3000);
      expect(jpy.totaleEur, closeTo(18.3, 0.0001));
      expect(jpy.countSenzaEur, 0);

      final aed = righe.last;
      expect(aed.count, 1);
      expect(aed.totale, 50);
      expect(aed.totaleEur, 0, reason: 'nothing converted yet');
      expect(aed.countSenzaEur, 1);
    });

    test('breakdownPerValuta puts the trip currency first', () async {
      await repo.insert(spesa(importo: 10000, valuta: 'JPY'));
      await repo.insert(spesa(importo: 5, valuta: 'EUR', importoEur: 5));
      final righe =
          await repo.breakdownPerValuta(trasfertaId, valutaTrasferta: 'EUR');
      expect(righe.map((r) => r.valuta).toList(), ['EUR', 'JPY']);
    });

    test('breakdownPerValuta on a trip without spese is empty', () async {
      final righe =
          await repo.breakdownPerValuta(trasfertaId, valutaTrasferta: 'EUR');
      expect(righe, isEmpty);
    });
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/repositories_test.dart
```

Atteso: FAIL in compilazione — `The method 'breakdownPerValuta' isn't defined for the type 'SpesaRepository'`.

- [ ] **Step 3: Implement the query**

In `lib/data/repositories/spesa_repository.dart` aggiungi l'import in cima, accanto agli altri:

```dart
import '../models/valuta_breakdown.dart';
```

E il metodo subito dopo `totaliPerValuta` (dopo la riga 75):

```dart
  /// Per-currency aggregation in one pass: how many spese, their total in the
  /// original currency, how much of it is converted, and how many still lack
  /// `importo_eur`. Replaces calling totaliPerValuta + totaleEur +
  /// countSenzaEur separately on the detail screen.
  Future<List<ValutaBreakdown>> breakdownPerValuta(int trasfertaId,
      {required String valutaTrasferta}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT valuta, '
        'COUNT(*) AS n, '
        'SUM(importo) AS totale, '
        'COALESCE(SUM(importo_eur), 0) AS totale_eur, '
        'SUM(CASE WHEN importo_eur IS NULL THEN 1 ELSE 0 END) AS senza_eur '
        'FROM spese WHERE trasferta_id = ? GROUP BY valuta',
        [trasfertaId]);
    return ordinaPerValuta([
      for (final row in rows)
        ValutaBreakdown(
          valuta: row['valuta'] as String,
          count: (row['n'] as num).toInt(),
          totale: (row['totale'] as num).toDouble(),
          totaleEur: (row['totale_eur'] as num).toDouble(),
          countSenzaEur: (row['senza_eur'] as num).toInt(),
        ),
    ], valutaTrasferta);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/repositories_test.dart
flutter analyze
```

Atteso: tutti i test del file verdi, zero issue.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/spesa_repository.dart test/repositories_test.dart
git commit -m "feat: add per-currency breakdown query to SpesaRepository"
```

---

### Task 4: ConversionBackfillService

**Files:**
- Create: `lib/services/currency/conversion_backfill_service.dart`
- Test: `test/conversion_backfill_test.dart`

**Interfaces:**
- Consumes: `ExchangeService.convert(...)` (Task 1, firma invariata), `SpesaRepository.getByTrasferta(int)` e `.update(Spesa)` (già esistenti), `Spesa` (già esistente).
- Produces:
  - `class BackfillOutcome` con campi finali `int convertite` e `int fallite`, costruttore `const BackfillOutcome({required this.convertite, required this.fallite})`, e getter `bool get nessunaConversione => convertite == 0;`
  - `class ConversionBackfillService` con costruttore posizionale `ConversionBackfillService(SpesaRepository, ExchangeService)` e metodo `Future<BackfillOutcome> run(int trasfertaId)`.

- [ ] **Step 1: Write the failing test**

Crea `test/conversion_backfill_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/services/currency/conversion_backfill_service.dart';
import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late SpesaRepository repo;
  late int trasfertaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = SpesaRepository(
        dbHelper, FotoRepository(dbHelper, basePathProvider: () async => '.'));
    final db = await dbHelper.database;
    trasfertaId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-15',
      'valuta_default': 'JPY',
      'archiviata': 0,
      'created_at': '2026-07-15T08:00:00.000',
    });
  });

  tearDown(() => dbHelper.close());

  Spesa spesa({
    double importo = 1000,
    String valuta = 'JPY',
    double? importoEur,
  }) =>
      Spesa(
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 15),
        categoria: Categoria.altro,
        importo: importo,
        valuta: valuta,
        importoEur: importoEur,
        createdAt: DateTime(2026, 7, 15, 10),
      );

  ConversionBackfillService serviceWith(MockClient client) =>
      ConversionBackfillService(
          repo, ExchangeService(SettingsService(), client: client));

  MockClient rateClient(double rate) => MockClient((request) async =>
      http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'JPY',
            'date': '2026-07-15',
            'rates': {'EUR': rate},
          }),
          200,
          headers: {'content-type': 'application/json'}));

  test('converts only the rows missing importo_eur', () async {
    final giaConvertita = await repo.insert(spesa(importoEur: 99));
    final daConvertire = await repo.insert(spesa(importo: 2000));

    final outcome = await serviceWith(rateClient(0.0061)).run(trasfertaId);

    expect(outcome.convertite, 1);
    expect(outcome.fallite, 0);
    expect((await repo.getById(giaConvertita))!.importoEur, 99,
        reason: 'an already converted spesa must not be touched');
    final aggiornata = await repo.getById(daConvertire);
    expect(aggiornata!.importoEur, closeTo(12.2, 0.0001));
    expect(aggiornata.tassoCambio, 0.0061);
  });

  test('a failed conversion leaves the row NULL and is counted', () async {
    await repo.insert(spesa());
    final client = MockClient((request) async => http.Response('down', 500));

    final outcome = await serviceWith(client).run(trasfertaId);

    expect(outcome.convertite, 0);
    expect(outcome.fallite, 1);
    expect(outcome.nessunaConversione, isTrue);
    final righe = await repo.getByTrasferta(trasfertaId);
    expect(righe.single.importoEur, isNull);
  });

  test('nothing to do yields a zeroed outcome without network', () async {
    await repo.insert(spesa(importoEur: 5));
    final client = MockClient((request) async {
      fail('no conversion should be attempted');
    });

    final outcome = await serviceWith(client).run(trasfertaId);

    expect(outcome.convertite, 0);
    expect(outcome.fallite, 0);
  });

  test('other fields of a converted spesa survive the update', () async {
    final id = await repo.insert(spesa(importo: 2000));
    await serviceWith(rateClient(0.0061)).run(trasfertaId);
    final aggiornata = await repo.getById(id);
    expect(aggiornata!.importo, 2000);
    expect(aggiornata.valuta, 'JPY');
    expect(aggiornata.categoria, Categoria.altro);
    expect(aggiornata.trasfertaId, trasfertaId);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/conversion_backfill_test.dart
```

Atteso: FAIL in compilazione — `Target of URI doesn't exist: '.../conversion_backfill_service.dart'`.

- [ ] **Step 3: Write the service**

Crea `lib/services/currency/conversion_backfill_service.dart`:

```dart
import '../../data/models/spesa.dart';
import '../../data/repositories/spesa_repository.dart';
import 'exchange_service.dart';

/// How a backfill run went, for the SnackBar the caller shows.
class BackfillOutcome {
  const BackfillOutcome({required this.convertite, required this.fallite});

  final int convertite;
  final int fallite;

  /// Nothing could be converted — usually offline, or a date outside the
  /// rate sources' history.
  bool get nessunaConversione => convertite == 0;
}

/// Fills in `importo_eur` for spese saved without a conversion (offline at
/// the time, or a currency no rate source covered back then). Triggered by
/// the user, never automatically: it costs network and writes to the DB.
///
/// Best-effort by construction: a spesa whose rate cannot be fetched is left
/// untouched and counted as failed, and the run always continues.
class ConversionBackfillService {
  const ConversionBackfillService(this._spese, this._exchange);

  final SpesaRepository _spese;
  final ExchangeService _exchange;

  Future<BackfillOutcome> run(int trasfertaId) async {
    final spese = await _spese.getByTrasferta(trasfertaId);
    var convertite = 0;
    var fallite = 0;
    for (final spesa in spese.where((s) => s.importoEur == null)) {
      final result = await _exchange.convert(
          amount: spesa.importo, from: spesa.valuta, date: spesa.data);
      if (result == null) {
        fallite++;
        continue;
      }
      await _spese.update(_conConversione(spesa, result));
      convertite++;
    }
    return BackfillOutcome(convertite: convertite, fallite: fallite);
  }

  /// Copy of [spesa] with the conversion filled in; every other field is
  /// carried over untouched (Spesa has no copyWith).
  Spesa _conConversione(Spesa spesa, ExchangeResult result) => Spesa(
        id: spesa.id,
        trasfertaId: spesa.trasfertaId,
        data: spesa.data,
        categoria: spesa.categoria,
        fornitore: spesa.fornitore,
        importo: spesa.importo,
        valuta: spesa.valuta,
        importoEur: result.amountEur,
        tassoCambio: result.rate,
        note: spesa.note,
        ocrEngine: spesa.ocrEngine,
        createdAt: spesa.createdAt,
      );
}
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/conversion_backfill_test.dart
flutter analyze
```

Atteso: 4 test verdi, zero issue.

- [ ] **Step 5: Commit**

```bash
git add lib/services/currency/conversion_backfill_service.dart test/conversion_backfill_test.dart
git commit -m "feat: add on-demand EUR conversion backfill for saved spese"
```

---

### Task 5: Breakdown negli export (report, PDF, CSV)

**Files:**
- Modify: `lib/services/export/trasferta_report.dart:33-121`
- Modify: `lib/services/export/pdf_export_service.dart:11-25` e `:111-147`
- Modify: `lib/services/export/csv_export_service.dart:34-43`
- Test: `test/export/` (i file esistenti del gruppo export)

**Interfaces:**
- Consumes: `ValutaBreakdown`, `ordinaPerValuta` (Task 2).
- Produces: `TrasfertaReport.breakdown` di tipo `List<ValutaBreakdown>`, valorizzato da `TrasfertaReport.build`. `coverEurNote(double totaleEur)` perde il secondo parametro.

- [ ] **Step 1: Write the failing tests**

Aggiungi in `test/export/pdf_export_service_test.dart` (adatta il nome del `group` a quello già presente nel file):

```dart
  test('coverEurNote is just the EUR total, or null when nothing converted',
      () {
    expect(coverEurNote(662.02), '≈ € 662,02');
    expect(coverEurNote(0), isNull,
        reason: 'per-currency rows already say what is missing');
  });
```

E in `test/export/trasferta_report_test.dart`, dentro il `main()` esistente. Gli helper `_trip({String valuta})` e `_spesa({...})` sono già definiti in cima a quel file (righe 7-34) e vanno riusati così come sono:

```dart
  test('build produces an ordered per-currency breakdown', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(valuta: 'JPY', importo: 1000, importoEur: 6.1),
      _spesa(valuta: 'JPY', importo: 2000, importoEur: 12.2),
      _spesa(valuta: 'AED', importo: 50),
    ]);

    expect(r.breakdown.map((b) => b.valuta).toList(), ['JPY', 'AED']);

    final jpy = r.breakdown.first;
    expect(jpy.count, 2);
    expect(jpy.totale, 3000);
    expect(jpy.totaleEur, closeTo(18.3, 0.0001));
    expect(jpy.countSenzaEur, 0);

    final aed = r.breakdown.last;
    expect(aed.count, 1);
    expect(aed.totale, 50);
    expect(aed.totaleEur, 0);
    expect(aed.countSenzaEur, 1);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```
flutter test test/export/
```

Atteso: FAIL — `coverEurNote` richiede ancora due argomenti; `report.breakdown` non esiste.

- [ ] **Step 3: Implement**

**3a.** In `lib/services/export/trasferta_report.dart`, aggiungi l'import:

```dart
import '../../data/models/valuta_breakdown.dart';
```

Aggiungi il campo alla classe (accanto a `totaliPerValuta`) e al costruttore:

```dart
  /// Per-currency detail: count + original total + converted total, ordered
  /// with the trip currency first. What the cover and the CSV summary show.
  final List<ValutaBreakdown> breakdown;
```

```dart
    required this.breakdown,
```

In `build`, sostituisci il blocco di ordinamento inline (righe 68-74) con il calcolo del breakdown, riusando `perValuta` già costruito sopra:

```dart
    final valutaTrasferta = trasferta.valutaDefault;
    final breakdown = ordinaPerValuta([
      for (final valuta in perValuta.keys)
        ValutaBreakdown(
          valuta: valuta,
          count: spese.where((s) => s.valuta == valuta).length,
          totale: perValuta[valuta]!,
          totaleEur: spese
              .where((s) => s.valuta == valuta && s.importoEur != null)
              .fold<double>(0, (sum, s) => sum + s.importoEur!),
          countSenzaEur: spese
              .where((s) => s.valuta == valuta && s.importoEur == null)
              .length,
        ),
    ], valutaTrasferta);
    final totaliPerValuta = {for (final b in breakdown) b.valuta: b.totale};
```

e passa `breakdown: breakdown,` nella costruzione finale del `TrasfertaReport`.

**3b.** In `lib/services/export/pdf_export_service.dart`, sostituisci `coverEurNote` (righe 11-25) con:

```dart
/// Cover EUR line: the converted total, or null when nothing is converted
/// (a "≈ € 0,00" would read as a zeroed trip). What is missing no longer
/// needs a note here — the per-currency rows carry the counts.
@visibleForTesting
String? coverEurNote(double totaleEur) =>
    totaleEur > 0 ? '≈ ${formatEur(totaleEur)}' : null;
```

Nel metodo `_cover`, sostituisci il ciclo sui totali per valuta (righe 131-136) con:

```dart
        for (final b in report.breakdown)
          pw.Text(
            '${b.valuta} · ${b.count} spes${b.count == 1 ? 'a' : 'e'} · '
            '${formatValuta(b.totale, b.valuta)}'
            '${b.valuta == 'EUR' || b.totaleEur == 0 ? '' : ' · ≈ ${formatEur(b.totaleEur)}'}',
            style: const pw.TextStyle(fontSize: 12),
          ),
        if (coverEurNote(report.totaleEur) case final note?) ...[
          pw.SizedBox(height: 2),
          pw.Text(note, style: const pw.TextStyle(fontSize: 11)),
        ],
```

**3c.** In `lib/services/export/csv_export_service.dart`, sostituisci la riga di sintesi (righe 34-43) con:

```dart
      const <String>[],
      const ['RIEPILOGO PER VALUTA'],
      const ['Valuta', 'N. spese', 'Totale', 'Totale EUR', 'Senza conversione'],
      for (final b in report.breakdown)
        [
          b.valuta,
          '${b.count}',
          _money(b.totale),
          _money(b.totaleEur),
          b.countSenzaEur == 0 ? '' : '${b.countSenzaEur}',
        ],
      const <String>[],
      [
        'TOTALE EUR',
        '', '', '', '',
        _money(report.totaleEur),
      ],
```

- [ ] **Step 4: Run the tests to verify they pass**

```
flutter test test/export/
flutter analyze
```

Atteso: verdi. Se un test preesistente asserisce la vecchia stringa `esclude N spese non convertite`, aggiornalo al nuovo formato — è un cambio di contratto voluto, non una regressione.

- [ ] **Step 5: Commit**

```bash
git add lib/services/export/ test/export/
git commit -m "feat: show per-currency breakdown in PDF cover and CSV summary"
```

---

### Task 6: Riepilogo per valuta e pulsante Ricalcola nel dettaglio

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart:30-68`
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart:518-569` (`_TotalsHeader`) e `_TrasfertaDetailScreenState` (nuovo campo `_ricalcolando` + metodo)
- Modify: `lib/ui/trasferte/trasferte_list_screen.dart:72-77` (unico sito di costruzione del controller in produzione)
- Modify: `pubspec.yaml:19`, `lib/version.dart:3`
- Modify: `ToDo.md`
- Test: `test/trasferta_detail_controller_test.dart`, `test/trasferta_detail_screen_test.dart`

**Interfaces:**
- Consumes: `breakdownPerValuta` (Task 3), `ConversionBackfillService.run` + `BackfillOutcome` (Task 4), `ValutaBreakdown` (Task 2).
- Produces: `TrasfertaDetailController.breakdown` (`List<ValutaBreakdown>`) e `TrasfertaDetailController.ricalcolaConversioni()` → `Future<BackfillOutcome>`.

- [ ] **Step 1: Write the failing tests**

In `test/trasferta_detail_controller_test.dart`:

```dart
  test('load fills the per-currency breakdown', () async {
    await spesaRepo.insert(spesaFixture(importo: 1000, valuta: 'JPY'));
    await spesaRepo.insert(spesaFixture(importo: 50, valuta: 'AED'));
    await controller.load();
    expect(controller.breakdown.map((b) => b.valuta).toList(),
        containsAll(<String>['JPY', 'AED']));
    expect(controller.breakdown.firstWhere((b) => b.valuta == 'AED').count, 1);
  });
```

(Adatta `spesaRepo` / `spesaFixture` / `controller` ai nomi già usati nel file.)

In `test/trasferta_detail_screen_test.dart` servono due modifiche.

**(a)** Estendi l'helper `pump` esistente (riga 171) con un parametro opzionale, così un test può iniettare il servizio di backfill. Aggiungi `ConversionBackfillService? backfill,` alla lista dei parametri nominali e passalo al controller:

```dart
        controller: TrasfertaDetailController(
            id ?? trasfertaId, trasfertaRepo, spesaRepo, fotoRepo, photoService,
            backfill: backfill),
```

Aggiungi l'import in cima al file di test:

```dart
import 'package:nota_spese/services/currency/conversion_backfill_service.dart';
```

**(b)** Aggiungi i test. `spesaRepo`, `trasfertaId` e `pump` sono già disponibili nello scope; `FakeExchangeService` è già importato da `fakes/fake_exchange_service.dart`:

```dart
  Spesa spesaFixture({
    double importo = 1000,
    String valuta = 'JPY',
    double? importoEur,
  }) =>
      Spesa(
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 10),
        categoria: Categoria.pranzo,
        importo: importo,
        valuta: valuta,
        importoEur: importoEur,
        createdAt: DateTime(2026, 7, 10, 12),
      );

  testWidgets('header shows count and amount per currency', (tester) async {
    await spesaRepo.insert(spesaFixture(importo: 1000, importoEur: 6.1));
    await spesaRepo.insert(spesaFixture(importo: 2000, importoEur: 12.2));
    await spesaRepo.insert(spesaFixture(importo: 50, valuta: 'AED'));
    await pump(tester);

    expect(find.textContaining('2 spese'), findsWidgets);
    expect(find.textContaining('1 spesa'), findsWidgets);
    expect(find.textContaining('≈'), findsWidgets);
  });

  testWidgets('Ricalcola is hidden when every spesa is converted',
      (tester) async {
    await spesaRepo.insert(spesaFixture(importoEur: 6.1));
    await pump(tester);
    expect(find.text('Ricalcola'), findsNothing);
  });

  testWidgets('Ricalcola appears when a conversion is missing',
      (tester) async {
    await spesaRepo.insert(spesaFixture());
    await pump(tester);
    expect(find.text('Ricalcola'), findsOneWidget);
  });

  testWidgets('tapping Ricalcola converts and reports the outcome',
      (tester) async {
    await spesaRepo.insert(spesaFixture(importo: 1000));
    await pump(tester,
        backfill: ConversionBackfillService(
            spesaRepo, FakeExchangeService(rate: 0.0061)));

    await tester.tap(find.byKey(const Key('ricalcola-conversioni')));
    await tester.pumpAndSettle();

    expect(find.text('Convertita 1 spesa'), findsOneWidget);
    expect(find.text('Ricalcola'), findsNothing,
        reason: 'nothing left to convert after a full run');
  });

  testWidgets('Ricalcola with no rate available says so', (tester) async {
    await spesaRepo.insert(spesaFixture(importo: 1000));
    await pump(tester,
        backfill:
            ConversionBackfillService(spesaRepo, FakeExchangeService()));

    await tester.tap(find.byKey(const Key('ricalcola-conversioni')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nessun tasso disponibile'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```
flutter test test/trasferta_detail_controller_test.dart test/trasferta_detail_screen_test.dart
```

Atteso: FAIL — `breakdown` non è definito sul controller; `Ricalcola` non esiste.

- [ ] **Step 3: Implement**

**3a. Controller.** In `lib/ui/trasferte/trasferta_detail_controller.dart` aggiungi gli import:

```dart
import '../../data/models/valuta_breakdown.dart';
import '../../services/currency/conversion_backfill_service.dart';
```

Aggiungi il servizio come parametro opzionale del costruttore (opzionale per non rompere i test esistenti che costruiscono il controller con 5 argomenti):

```dart
  TrasfertaDetailController(this.trasfertaId, this._trasfertaRepository,
      this._spesaRepository, this._fotoRepository, this._photoService,
      {ConversionBackfillService? backfill})
      : _backfill = backfill;

  final ConversionBackfillService? _backfill;
```

Aggiungi il campo accanto a `totaliPerValuta`:

```dart
  List<ValutaBreakdown> breakdown = [];
```

In `load()`, subito dopo `totaliPerValuta = await ...` (riga 56):

```dart
    breakdown = await _spesaRepository.breakdownPerValuta(trasfertaId,
        valutaTrasferta: trasferta?.valutaDefault ?? 'EUR');
```

E il metodo pubblico:

```dart
  /// User-triggered backfill of the missing EUR conversions. Returns a
  /// zeroed outcome when no backfill service is wired (tests, previews).
  Future<BackfillOutcome> ricalcolaConversioni() async {
    final backfill = _backfill;
    if (backfill == null) {
      return const BackfillOutcome(convertite: 0, fallite: 0);
    }
    final outcome = await backfill.run(trasfertaId);
    if (outcome.convertite > 0) await load();
    return outcome;
  }
```

**3b. Header.** In `lib/ui/trasferte/trasferta_detail_screen.dart`, sostituisci il corpo di `_TotalsHeader` (righe 529-565, la `Column`) con:

```dart
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totale trasferta',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            for (final b in controller.breakdown) ...[
              Text(
                formatValuta(b.totale, b.valuta),
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: amountFontFeatures,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${b.count} spes${b.count == 1 ? 'a' : 'e'}'
                // The EUR hint is redundant on a EUR row, and misleading as
                // "≈ € 0,00" when nothing in this currency is converted.
                '${b.valuta == 'EUR' || b.totaleEur == 0 ? '' : ' · ≈ ${formatEur(b.totaleEur)}'}',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (controller.countSenzaEur > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('ricalcola-conversioni'),
                  // Disabling while in flight (onPressed: null) also stops a
                  // second tap from launching a parallel run.
                  icon: ricalcolando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Symbols.currency_exchange, size: 18),
                  label: Text(ricalcolando ? 'Conversione…' : 'Ricalcola'),
                  onPressed: ricalcolando ? null : onRicalcola,
                ),
              ),
          ],
        ),
```

Aggiungi i parametri al costruttore di `_TotalsHeader`:

```dart
  const _TotalsHeader({
    required this.controller,
    required this.onRicalcola,
    required this.ricalcolando,
  });

  final TrasfertaDetailController controller;
  final VoidCallback onRicalcola;
  final bool ricalcolando;
```

Nel punto in cui `_TotalsHeader` viene costruito, passa `onRicalcola: _ricalcolaConversioni` e `ricalcolando: _ricalcolando`. Nello `_TrasfertaDetailScreenState` aggiungi il campo accanto a `_claudeAvailable`:

```dart
  bool _ricalcolando = false;
```

e il metodo:

```dart
  Future<void> _ricalcolaConversioni() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ricalcolando = true);
    final BackfillOutcome outcome;
    try {
      outcome = await controller.ricalcolaConversioni();
    } finally {
      if (mounted) setState(() => _ricalcolando = false);
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(_esito(outcome))));
  }

  /// Italian agreement: "Convertita 1 spesa" vs "Convertite 3 spese".
  String _esito(BackfillOutcome outcome) {
    if (outcome.nessunaConversione) {
      return 'Nessun tasso disponibile: controlla la connessione';
    }
    final n = outcome.convertite;
    final testa = n == 1 ? 'Convertita 1 spesa' : 'Convertite $n spese';
    if (outcome.fallite == 0) return testa;
    return '$testa su ${n + outcome.fallite}';
  }
```

Aggiungi l'import di `conversion_backfill_service.dart` in cima allo screen (serve il tipo `BackfillOutcome`).

**3c. Wiring.** L'unico punto di produzione che costruisce il controller è `lib/ui/trasferte/trasferte_list_screen.dart:72-77` (dentro `_openDetail`). Sostituisci quella costruzione con:

```dart
        controller: TrasfertaDetailController(
            trasfertaId,
            widget.trasfertaRepository,
            widget.spesaRepository,
            widget.fotoRepository,
            widget.photoService,
            backfill: ConversionBackfillService(
                widget.spesaRepository, widget.exchangeService)),
```

e aggiungi in cima al file:

```dart
import '../../services/currency/conversion_backfill_service.dart';
```

**3d. Versione e ToDo.** In `pubspec.yaml` riga 19: `version: 0.12.0+17`. In `lib/version.dart` riga 3: `const String appVersion = '0.12.0';`.

In `ToDo.md`, spunta la voce aggiunta in fase 7 e sostituiscine il testo con un resoconto di cosa è stato fatto (catena BCE→fallback, breakdown per valuta, pulsante Ricalcola, nessuna modifica di schema), citando la spec `docs/superpowers/specs/2026-07-30-conversione-tutte-le-valute-design.md`. Aggiorna anche la nota di fase 6 che dichiara "RSD e AED senza conversione automatica" e la "Nota post-fix BUG-01" sulle spese da riaprire a mano, ora risolta dal pulsante Ricalcola.

- [ ] **Step 4: Run the whole suite**

```
flutter test
flutter analyze
```

Atteso: tutti i test verdi (i 427 preesistenti più i nuovi), zero issue. Se un widget test preesistente asserisce la vecchia stringa `N spese senza conversione EUR` nell'header, aggiornalo: quella riga è stata sostituita dal breakdown più il pulsante.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/ pubspec.yaml lib/version.dart ToDo.md test/
git commit -m "feat: per-currency summary and on-demand reconversion in trip detail"
```

---

## Verifica finale (fine piano)

- [ ] `flutter analyze` → zero issue
- [ ] `flutter test` → tutto verde
- [ ] Prova manuale su device (rimandabile come le altre di fase 6b se il device non è disponibile): trasferta con una spesa in AED → l'importo EUR viene compilato; trasferta con spese vecchie non convertite → "Ricalcola" le converte e la SnackBar riporta i conteggi.
- [ ] `ToDo.md` aggiornato con lo stato reale (incluse le note di fase 6 e BUG-01 superate)

## Non incluso di proposito

- Migrazione di `trip_card` / lista trasferte al breakdown (ridurrebbe 3 query a 1 per trasferta, indipendente dalla richiesta).
- Colonna "fonte del tasso" in DB (richiederebbe una migrazione di schema).
- Nuovo layout grafico del PDF (mockup C blu): modifica successiva e separata.
