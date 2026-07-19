# Fase 6 — Conversione EUR (frankfurter.app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** conversione EUR live nel form spesa via tassi storici frankfurter.app, mai bloccante, con badge AUTO, ricalcolo manuale e toggle in Impostazioni.

**Architecture:** nuovo `ExchangeService` (fetch diretto + cache in-memory di sessione, `null` su qualsiasi fallimento) iniettato a costruttore lungo la catena `main → NotaSpeseApp → HomeShell → TrasferteListScreen → TrasfertaDetailScreen → SpesaFormScreen`. Conversione live con debounce solo in creazione; su spesa esistente MAI ricalcolo automatico (solo pulsante). Spec di riferimento: `docs/superpowers/specs/2026-07-19-fase-6-conversione-eur-design.md`.

**Tech Stack:** Flutter/Dart, `http` (già in pubspec) + `MockClient` per i test, `shared_preferences` per il toggle.

## Global Constraints

- `flutter analyze` → zero issue a fine di OGNI task.
- Test esistenti sempre verdi (230 al momento della scrittura).
- Codice/commenti/commit in inglese; testi UI in italiano.
- Nessun accesso http/filesystem dai controller/UI: solo tramite service.
- Nessun log/errore che blocchi il flusso di salvataggio spesa: ogni fallimento conversione → `null` silenzioso.
- Bump versione (`pubspec.yaml` + `lib/version.dart`) solo nel task finale: `0.6.0+6` → `0.7.0+7`.
- Git: lavorare su branch `fase-6-valuta`; commit a fine task (autorizzazione branch+commit da chiedere all'utente PRIMA di iniziare, come in fase 5). Messaggi Conventional Commits.
- Gotcha test noti (da CLAUDE.md/memoria): niente IO reale nel body di `testWidgets`; `FutureBuilder`/future cacheati, mai creati in `build`; debounce = `Timer` → cancellarlo in `dispose` altrimenti flutter_test fallisce con "Timer is still pending".
- **Limite dati noto:** frankfurter espone solo le ~30 valute ECB — **RSD e AED non coperte** → `convert` ritorna `null`, campo EUR resta manuale. Comportamento accettato dal design (nessun errore); annotato in ToDo nel task finale.

---

### Task 1: Toggle `tassi_online` in SettingsService

**Files:**
- Modify: `lib/services/settings/settings_service.dart`
- Test: `test/settings_service_test.dart`

**Interfaces:**
- Produces: `Future<bool> get tassiOnline` (default `true`), `Future<void> setTassiOnline(bool value)` — usati da Task 2 (ExchangeService) e Task 3 (UI toggle).

- [ ] **Step 1: Write the failing tests**

In `test/settings_service_test.dart`, aggiungere nel `main()` (seguire il pattern dei test esistenti nel file, che usano `SharedPreferences.setMockInitialValues`):

```dart
group('tassiOnline', () {
  test('default is true when unset', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SettingsService().tassiOnline, isTrue);
  });

  test('setTassiOnline persists false', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();
    await service.setTassiOnline(false);
    expect(await service.tassiOnline, isFalse);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/settings_service_test.dart`
Expected: FAIL — `tassiOnline` non definito (errore di compilazione).

- [ ] **Step 3: Implement**

In `lib/services/settings/settings_service.dart`, dentro `SettingsService` (stesso stile dei getter esistenti):

```dart
static const String _kTassiOnline = 'tassi_online';

/// Fase 6: master switch for frankfurter.app calls (Settings toggle).
Future<bool> get tassiOnline async =>
    (await SharedPreferences.getInstance()).getBool(_kTassiOnline) ?? true;

Future<void> setTassiOnline(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTassiOnline, value);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/settings_service_test.dart`
Expected: PASS (tutti, inclusi i preesistenti).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze` → zero issue.

```bash
git add lib/services/settings/settings_service.dart test/settings_service_test.dart
git commit -m "feat: add tassi_online setting (default on)"
```

---

### Task 2: ExchangeService (frankfurter.app, tassi storici)

**Files:**
- Create: `lib/services/currency/exchange_service.dart`
- Test: `test/exchange_service_test.dart` (nuovo)

**Interfaces:**
- Consumes: `SettingsService.tassiOnline` (Task 1).
- Produces (per Task 3):

```dart
class ExchangeResult {
  const ExchangeResult({required this.amountEur, required this.rate});
  final double amountEur; // amount * rate
  final double rate;      // 1 unità valuta origine = rate EUR
}

class ExchangeService {
  ExchangeService(SettingsService settings,
      {http.Client? client, Duration timeout = const Duration(seconds: 5)});
  Future<ExchangeResult?> convert(
      {required double amount, required String from, required DateTime date});
}
```

`convert` NON è mai throw: ritorna `null` per toggle off, offline, timeout, HTTP ≠ 200, JSON malformato, valuta non supportata (frankfurter → 404). `from == 'EUR'` → corto-circuito `rate 1.0` senza rete. Il metodo deve restare override-abile (i widget test del Task 3 lo sostituiscono con un fake).

- [ ] **Step 1: Write the failing tests**

Create `test/exchange_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response ok(double rate, {String date = '2026-07-10'}) => http.Response(
      jsonEncode({
        'amount': 1.0,
        'base': 'JPY',
        'date': date,
        'rates': {'EUR': rate},
      }),
      200,
      headers: {'content-type': 'application/json'});

  ExchangeService service(MockClient client) {
    SharedPreferences.setMockInitialValues({});
    return ExchangeService(SettingsService(), client: client);
  }

  test('historic rate: calls /yyyy-MM-dd?from=X&to=EUR and converts', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061);
    });
    final result = await service(client).convert(
        amount: 1200, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(seen.path, '/2026-07-10');
    expect(seen.queryParameters, {'from': 'JPY', 'to': 'EUR'});
    expect(result!.rate, 0.0061);
    expect(result.amountEur, closeTo(7.32, 0.0001));
  });

  test('date components are zero-padded', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061, date: '2026-01-05');
    });
    await service(client)
        .convert(amount: 1, from: 'JPY', date: DateTime(2026, 1, 5));
    expect(seen.path, '/2026-01-05');
  });

  test('EUR short-circuits without any network call', () async {
    final client = MockClient((request) async {
      fail('network must not be touched for EUR');
    });
    final result = await service(client)
        .convert(amount: 42.5, from: 'EUR', date: DateTime(2026, 7, 10));
    expect(result!.rate, 1.0);
    expect(result.amountEur, 42.5);
  });

  test('HTTP 404 (unsupported currency, e.g. RSD) returns null', () async {
    final client = MockClient((request) async => http.Response('not found', 404));
    expect(
        await service(client)
            .convert(amount: 10, from: 'RSD', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('HTTP 500 returns null', () async {
    final client = MockClient((request) async => http.Response('boom', 500));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('SocketException (offline) returns null', () async {
    final client = MockClient((request) async {
      throw const SocketException('offline');
    });
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('timeout returns null', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return ok(0.0061);
    });
    SharedPreferences.setMockInitialValues({});
    final s = ExchangeService(SettingsService(),
        client: client, timeout: const Duration(milliseconds: 50));
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('malformed JSON returns null', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('missing rates key returns null', () async {
    final client =
        MockClient((request) async => http.Response(jsonEncode({'a': 1}), 200));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('same date+currency is served from cache (single fetch)', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return ok(0.0061);
    });
    final s = service(client);
    await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10));
    await s.convert(amount: 99, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(calls, 1);
    await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 11));
    expect(calls, 2);
  });

  test('failed fetch is not cached (retry hits network again)', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1 ? http.Response('boom', 500) : ok(0.0061);
    });
    final s = service(client);
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
    final retry =
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(retry!.rate, 0.0061);
    expect(calls, 2);
  });

  test('tassi_online off returns null without network', () async {
    final client = MockClient((request) async {
      fail('network must not be touched when toggle is off');
    });
    SharedPreferences.setMockInitialValues({'tassi_online': false});
    final s = ExchangeService(SettingsService(), client: client);
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/exchange_service_test.dart`
Expected: FAIL — file `exchange_service.dart` inesistente (errore import).

- [ ] **Step 3: Implement**

Create `lib/services/currency/exchange_service.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/settings_service.dart';

/// Result of a EUR conversion: converted amount plus the rate used
/// (1 unit of the source currency = [rate] EUR).
class ExchangeResult {
  const ExchangeResult({required this.amountEur, required this.rate});

  final double amountEur;
  final double rate;
}

/// EUR conversion via frankfurter.app historical rates (fase 6 design).
/// Never throws toward callers: ANY failure — toggle off, offline, timeout,
/// non-200, malformed JSON, unsupported currency (frankfurter → 404, e.g.
/// RSD/AED are outside the ECB set) — returns null so the expense flow is
/// never blocked.
class ExchangeService {
  ExchangeService(this._settings,
      {http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  final SettingsService _settings;
  final http.Client _client;
  final Duration timeout;

  /// Session cache: 'yyyy-MM-dd|CUR' → rate. Historical rates never change,
  /// so entries stay valid for the whole app run.
  final Map<String, double> _rateCache = {};

  Future<ExchangeResult?> convert({
    required double amount,
    required String from,
    required DateTime date,
  }) async {
    if (from == 'EUR') return ExchangeResult(amountEur: amount, rate: 1.0);
    if (!await _settings.tassiOnline) return null;
    final day = _isoDay(date);
    final cacheKey = '$day|$from';
    var rate = _rateCache[cacheKey];
    if (rate == null) {
      rate = await _fetchRate(day, from);
      if (rate == null) return null;
      _rateCache[cacheKey] = rate;
    }
    return ExchangeResult(amountEur: amount * rate, rate: rate);
  }

  Future<double?> _fetchRate(String day, String from) async {
    final uri =
        Uri.https('api.frankfurter.app', '/$day', {'from': from, 'to': 'EUR'});
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) return null;
      final rate = rates['EUR'];
      return rate is num ? rate.toDouble() : null;
    } on Exception {
      // TimeoutException, SocketException, ClientException, FormatException:
      // all mapped to "no rate available".
      return null;
    }
  }

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/exchange_service_test.dart`
Expected: PASS (12 test).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze` → zero issue.

```bash
git add lib/services/currency/exchange_service.dart test/exchange_service_test.dart
git commit -m "feat: exchange service with frankfurter historical rates"
```

---

### Task 3: Conversione live nel form spesa + iniezione servizio

**Files:**
- Modify: `lib/ui/spese/spesa_form_screen.dart`
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart` (nuovo param + pass-through)
- Modify: `lib/ui/trasferte/trasferte_list_screen.dart` (pass-through)
- Modify: `lib/ui/shell/home_shell.dart` (pass-through, SOLO plumbing — la UI del toggle è Task 4)
- Modify: `lib/app.dart`, `lib/main.dart` (creazione + pass-through)
- Create: `test/fakes/fake_exchange_service.dart`
- Test: `test/spesa_form_screen_test.dart` (nuovi test + fix costruttori), fix costruttori in `test/trasferta_detail_screen_test.dart`, `test/trasferte_list_screen_test.dart`, `test/home_shell_test.dart`, `test/widget_test.dart` (dove costruiscono i widget toccati)

**Interfaces:**
- Consumes: `ExchangeService.convert(...)` / `ExchangeResult` (Task 2).
- Produces: `SpesaFormScreen` nuovo param `required ExchangeService exchange`; `TrasfertaDetailScreen`/`TrasferteListScreen`/`HomeShell`/`NotaSpeseApp` nuovo param `required ExchangeService exchangeService`. Keys per test: `Key('eur-ricalcola')`.

**Regole comportamento (dalla spec, decisioni utente):**
1. Conversione live SOLO in creazione (`widget.initial == null`), con debounce 600 ms su: cambio importo (listener su `_importo`), cambio valuta, cambio data, e una volta in `initState` (pre-fill OCR).
2. Edit manuale del campo EUR (`onChanged`, solo input utente) → stato manuale: badge via, stop auto per sempre (nel form corrente).
3. Spesa esistente: NESSUNA conversione automatica, mai. Solo pulsante ricalcolo.
4. Pulsante ricalcolo (suffixIcon del campo EUR, key `eur-ricalcola`): sempre visibile quando il campo EUR è visibile; forza fetch immediato, sovrascrive anche valore manuale e ripristina stato AUTO; su `null` → SnackBar 'Tasso non disponibile'.
5. Badge AUTO = `helperText` del campo: `AUTO · 1 JPY = 0,0061 €` (tasso `toStringAsFixed(4)`, virgola decimale).
6. Salvataggio: AUTO → `tassoCambio = rate`; manuale/vuoto → `tassoCambio = null`; valuta EUR → `importoEur = importo`, `tassoCambio = null`. ATTENZIONE: sostituisce l'attuale `tassoCambio: initial?.tassoCambio` in `_salva`; in edit senza tocchi lo stato AUTO iniziale (`initial.tassoCambio != null`) ripreserva lo stesso valore.
7. Risultato fetch scartato se nel frattempo l'importo è cambiato (guard anti-race) o il widget è unmounted.
8. `Timer` di debounce cancellato in `dispose` (gotcha flutter_test).

- [ ] **Step 1: Create the shared fake**

Create `test/fakes/fake_exchange_service.dart`:

```dart
import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';

/// Widget-test double: fixed [rate] (null → simulate offline/unsupported),
/// counts calls. Never touches SharedPreferences or the network.
class FakeExchangeService extends ExchangeService {
  FakeExchangeService({this.rate}) : super(SettingsService());

  double? rate;
  int calls = 0;

  @override
  Future<ExchangeResult?> convert({
    required double amount,
    required String from,
    required DateTime date,
  }) async {
    calls++;
    final r = rate;
    return r == null ? null : ExchangeResult(amountEur: amount * r, rate: r);
  }
}
```

- [ ] **Step 2: Write the failing widget tests**

In `test/spesa_form_screen_test.dart` aggiungere un group `conversione EUR live` (adattare l'helper di build esistente del file: aggiungere `exchange` come parametro, default `FakeExchangeService()`):

```dart
group('conversione EUR live', () {
  testWidgets('pre-fill OCR + debounce → campo EUR AUTO con tasso',
      (tester) async {
    final exchange = FakeExchangeService(rate: 0.0061);
    await pumpForm(tester,
        valutaDefault: 'JPY',
        exchange: exchange,
        parsed: ParsedReceipt(
            importo: 1200,
            valuta: 'JPY',
            data: DateTime(2026, 7, 10),
            fornitore: 'Lawson',
            lingua: 'ja',
            engine: OcrEngine.mlkit,
            rawText: 'x'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('7,32'), findsOneWidget); // 1200 * 0.0061 nel campo EUR
    expect(find.textContaining('AUTO · 1 JPY ='), findsOneWidget);
    expect(exchange.calls, 1);
  });

  testWidgets('salvataggio AUTO persiste tassoCambio', (tester) async {
    Spesa? saved;
    final exchange = FakeExchangeService(rate: 0.0061);
    await pumpForm(tester,
        valutaDefault: 'JPY',
        exchange: exchange,
        parsed: parsedJpy1200(), // helper: come sopra
        onSave: (s, {nuovaFoto, rimuoviFoto = false}) async => saved = s);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(saved!.tassoCambio, 0.0061);
    expect(saved!.importoEur, closeTo(7.32, 0.001));
  });

  testWidgets('edit manuale del campo EUR toglie AUTO e azzera tasso',
      (tester) async {
    Spesa? saved;
    final exchange = FakeExchangeService(rate: 0.0061);
    await pumpForm(tester,
        valutaDefault: 'JPY',
        exchange: exchange,
        parsed: parsedJpy1200(),
        onSave: (s, {nuovaFoto, rimuoviFoto = false}) async => saved = s);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('campo-importo-eur')), '8,00');
    await tester.pump();
    expect(find.textContaining('AUTO ·'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(saved!.tassoCambio, isNull);
    expect(saved!.importoEur, 8.0);
  });

  testWidgets('offline: campo resta vuoto, salvataggio senza EUR ok',
      (tester) async {
    Spesa? saved;
    await pumpForm(tester,
        valutaDefault: 'JPY',
        exchange: FakeExchangeService(rate: null),
        parsed: parsedJpy1200(),
        onSave: (s, {nuovaFoto, rimuoviFoto = false}) async => saved = s);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.textContaining('AUTO ·'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(saved!.importoEur, isNull);
    expect(saved!.tassoCambio, isNull);
  });

  testWidgets('spesa esistente: nessuna conversione automatica',
      (tester) async {
    final exchange = FakeExchangeService(rate: 0.0061);
    await pumpForm(tester,
        valutaDefault: 'JPY',
        exchange: exchange,
        initial: spesaJpyEsistente()); // helper esistente/nuovo del file
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
    await tester.enterText(find.byKey(const Key('campo-importo-eur')), '9,99');
    await tester.ensureVisible(find.byKey(const Key('eur-ricalcola')));
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
    await tester.ensureVisible(find.byKey(const Key('eur-ricalcola')));
    await tester.tap(find.byKey(const Key('eur-ricalcola')));
    await tester.pumpAndSettle();
    expect(find.text('Tasso non disponibile'), findsOneWidget);
  });
});
```

Note per l'esecutore: `pumpForm`/gli helper esistono già in forma simile nel file (adattare i nomi reali); i finder `ensureVisible` servono per la `ListView` (gotcha viewport). Se un helper `parsedJpy1200`/`spesaJpyEsistente` non esiste, crearlo locale al file con i campi mostrati sopra.

- [ ] **Step 3: Run new tests to verify they fail**

Run: `flutter test test/spesa_form_screen_test.dart`
Expected: FAIL — param `exchange` inesistente (compilazione).

- [ ] **Step 4: Implement — SpesaFormScreen**

Modifiche a `lib/ui/spese/spesa_form_screen.dart`:

1. Import: `import 'dart:async';` e `import '../../services/currency/exchange_service.dart';`
2. Widget: nuovo campo `final ExchangeService exchange;` + `required this.exchange` nel costruttore.
3. State — nuovi membri:

```dart
// Fase 6 live conversion state. AUTO = the EUR field holds a value computed
// from _eurRate; a manual user edit clears it permanently for this form
// (design decision: no silent recalculation, refresh button only).
Timer? _convertDebounce;
bool _eurManual = false;
late bool _eurAuto = widget.initial?.tassoCambio != null;
late double? _eurRate = widget.initial?.tassoCambio;
```

4. `initState` (nuovo override):

```dart
@override
void initState() {
  super.initState();
  _importo.addListener(_scheduleConvert);
  _scheduleConvert(); // OCR pre-fill: convert what's already in the form
}
```

5. Metodi conversione:

```dart
/// Creation only, until the user edits the EUR field by hand. Existing
/// expenses are never auto-recalculated (refresh button only).
void _scheduleConvert() {
  if (widget.initial != null || _eurManual || _valuta == 'EUR') return;
  _convertDebounce?.cancel();
  _convertDebounce =
      Timer(const Duration(milliseconds: 600), () => _convertNow());
}

Future<void> _convertNow({bool force = false}) async {
  final importo = _importo.amount;
  if (importo == null || importo <= 0 || _valuta == 'EUR') return;
  final result = await widget.exchange
      .convert(amount: importo, from: _valuta, date: _data);
  // Discard stale results: amount changed while the fetch was in flight.
  if (!mounted || _importo.amount != importo) return;
  if (result == null) {
    if (force) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasso non disponibile')));
    }
    return;
  }
  setState(() {
    _importoEur.text =
        result.amountEur.toStringAsFixed(2).replaceAll('.', ',');
    _eurAuto = true;
    _eurRate = result.rate;
  });
}

void _onEurEdited(String _) {
  setState(() {
    _eurManual = true;
    _eurAuto = false;
    _eurRate = null;
  });
}

Future<void> _ricalcola() async {
  _eurManual = false;
  await _convertNow(force: true);
}
```

6. `_pickValuta`: dopo il `setState` esistente aggiungere `_scheduleConvert();`. Idem in `_pickData` dopo `setState(() => _data = picked);`.
7. `dispose`: aggiungere `_convertDebounce?.cancel();` e `_importo.removeListener(_scheduleConvert);` prima di `_importo.dispose();`.
8. Campo EUR — sostituire la `decoration` const e aggiungere `onChanged`:

```dart
TextFormField(
  key: const Key('campo-importo-eur'),
  controller: _importoEur,
  decoration: InputDecoration(
    labelText: 'Importo EUR (opzionale)',
    helperText: _eurAuto && _eurRate != null
        ? 'AUTO · 1 $_valuta = '
            '${_eurRate!.toStringAsFixed(4).replaceAll('.', ',')} €'
        : null,
    suffixIcon: IconButton(
      key: const Key('eur-ricalcola'),
      icon: const Icon(Symbols.currency_exchange),
      tooltip: 'Ricalcola tasso',
      onPressed: _ricalcola,
    ),
  ),
  onChanged: _onEurEdited,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  validator: (v) { /* invariato */ },
),
```

9. `_salva`: sostituire `tassoCambio: initial?.tassoCambio,` con:

```dart
tassoCambio:
    _valuta == 'EUR' ? null : (_eurAuto && importoEur != null ? _eurRate : null),
```

- [ ] **Step 5: Implement — plumbing**

Con lo stesso pattern dei param esistenti (`orchestrator`, `settingsService`):
- `lib/ui/trasferte/trasferta_detail_screen.dart`: import exchange_service, campo `final ExchangeService exchangeService;` + required nel costruttore; in `_openSpesaForm` passare `exchange: widget.exchangeService,` a `SpesaFormScreen`.
- `lib/ui/trasferte/trasferte_list_screen.dart`: campo + required + pass a `TrasfertaDetailScreen(exchangeService: widget.exchangeService, ...)`.
- `lib/ui/shell/home_shell.dart`: campo + required su `HomeShell`; pass alle due `TrasferteListScreen`.
- `lib/app.dart`: campo + required su `NotaSpeseApp`; pass a `HomeShell`.
- `lib/main.dart`: dopo `final apiKeyStore = ...` aggiungere `final exchangeService = ExchangeService(settingsService);` e passarlo a `runApp(NotaSpeseApp(... exchangeService: exchangeService, ...))`.

- [ ] **Step 6: Fix existing test constructors**

`flutter test` segnalerà i costruttori incompleti. In `test/trasferta_detail_screen_test.dart`, `test/trasferte_list_screen_test.dart`, `test/home_shell_test.dart`, `test/widget_test.dart` (dove serve): aggiungere `exchangeService: FakeExchangeService(),` (import di `fakes/fake_exchange_service.dart`). Nei flussi e2e di quei file il fake con `rate: null` = nessuna conversione, comportamento pre-esistente.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS (230 preesistenti + 7 nuovi).

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze` → zero issue.

```bash
git add lib test
git commit -m "feat: live eur conversion in expense form via exchange service"
```

---

### Task 4: Toggle "Tassi di cambio online" in Impostazioni

**Files:**
- Modify: `lib/ui/shell/home_shell.dart` (`ImpostazioniMinimal`)
- Test: `test/home_shell_test.dart`

**Interfaces:**
- Consumes: `SettingsService.tassiOnline` / `setTassiOnline` (Task 1).
- Produces: `SwitchListTile` con key `Key('toggle-tassi-online')`.

- [ ] **Step 1: Write the failing tests**

In `test/home_shell_test.dart` (pattern esistente del file per navigare al tab Impostazioni e mockare SharedPreferences):

```dart
testWidgets('toggle tassi online: default ON, tap persiste OFF',
    (tester) async {
  SharedPreferences.setMockInitialValues({});
  await pumpShell(tester); // helper esistente del file
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/home_shell_test.dart`
Expected: FAIL — key `toggle-tassi-online` non trovata.

- [ ] **Step 3: Implement**

In `_ImpostazioniMinimalState`:
1. Stato: `bool _tassiOnline = true;`
2. In `_load()` aggiungere `final tassi = await widget.settingsService.tassiOnline;` e nel `setState` `_tassiOnline = tassi;`.
3. Handler:

```dart
Future<void> _onTassiOnlineChanged(bool value) async {
  await widget.settingsService.setTassiOnline(value);
  if (!mounted) return;
  setState(() => _tassiOnline = value);
}
```

4. Nel `ListView`, dopo la card "Motore OCR predefinito" (prima del footer versione), nuova card coerente con le esistenti:

```dart
const SizedBox(height: 16),
Card(
  child: SwitchListTile(
    key: const Key('toggle-tassi-online'),
    title: const Text('Tassi di cambio online'),
    subtitle: const Text(
        'Conversione EUR automatica via frankfurter.app (tasso del giorno della spesa)'),
    value: _tassiOnline,
    onChanged: _onTassiOnlineChanged,
  ),
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/home_shell_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze` → zero issue.

```bash
git add lib/ui/shell/home_shell.dart test/home_shell_test.dart
git commit -m "feat: online exchange rates toggle in settings"
```

---

### Task 5: Chiusura fase — versione, docs, verifica completa

**Files:**
- Modify: `pubspec.yaml` (riga 19: `version: 0.6.0+6` → `version: 0.7.0+7`)
- Modify: `lib/version.dart` (`'0.6.0'` → `'0.7.0'`)
- Modify: `ToDo.md` (fase 6), `Specifiche.md` (§3 Valuta Multipla)

**Interfaces:** nessuna — solo chiusura.

- [ ] **Step 1: Bump version**

`pubspec.yaml`: `version: 0.7.0+7`. `lib/version.dart`: `const String appVersion = '0.7.0';`

- [ ] **Step 2: Update ToDo.md fase 6**

Spuntare le checkbox implementate e annotare le decisioni:
- `[x] exchange_service.dart` — aggiungere alla riga: "(tasso storico alla data della spesa; cache in-memory sessione)".
- `[x]` conversione con badge AUTO — correggere la riga: conversione **live nel form** con debounce (design 2026-07-19), non al salvataggio.
- `[x]` offline/manuale + pulsante ricalcolo.
- `[x]` toggle Impostazioni.
- `[x]` totali: già implementati in fase 3 (`countSenzaEur` nell'header) — annotare "già coperto da fase 3, nessuna modifica".
- `[x]` unit test conversione.
- Aggiungere nota limite: "⚠️ frankfurter copre solo le ~30 valute ECB: **RSD e AED senza conversione automatica** (campo EUR manuale); eventuale API alternativa → v1.1".
- Verifica fase 6: spuntare la riga test/analyze; la prova su device resta **SKIP esplicito** (gotcha ambiente Android) con nota "compensata da unit + widget test con MockClient/fake".

- [ ] **Step 3: Update Specifiche.md §3**

Nella sezione "Valuta Multipla", aggiornare il bullet "Conversione EUR — non obbligatoria" per riflettere il design approvato: conversione **live nel form** (debounce) col tasso **storico alla data della spesa**; mai ricalcolo automatico su spese esistenti (solo pulsante); toggle "Tassi di cambio online"; limite valute ECB (no RSD/AED).

- [ ] **Step 4: Full verification**

Run: `flutter analyze` → zero issue.
Run: `flutter test` → tutto verde (≈238+ test).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/version.dart ToDo.md Specifiche.md
git commit -m "chore: close phase 6 - bump 0.7.0+7, update todo and specs"
```
