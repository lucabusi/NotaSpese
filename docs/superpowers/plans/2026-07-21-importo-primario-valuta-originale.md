# Importo primario nella valuta originale — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrare in primo piano i totali nella valuta originale delle spese, con la conversione EUR come informazione secondaria che sparisce quando non è disponibile.

**Architecture:** Nessuna modifica al DB. Un nuovo formatter (`formatValuta`) applica simbolo e decimali della valuta ISO; il `SpesaRepository` guadagna un'aggregazione per categoria in valuta originale; i due controller espongono i totali per valuta già presenti nel DB; le tre superfici UI (header dettaglio, card lista, header lista) cambiano solo il modo di renderizzarli.

**Tech Stack:** Flutter, Dart, sqflite (`sqflite_common_ffi` nei test), `intl`, `flutter_test`.

Spec di riferimento: `docs/superpowers/specs/2026-07-21-importo-primario-valuta-originale-design.md`

## Global Constraints

- Lingua: codice, nomi e commenti in inglese; stringhe UI in italiano.
- `flutter analyze` deve restare a zero issue dopo ogni task.
- Bump di `appVersion` in `lib/version.dart` + `version:` in `pubspec.yaml` una sola volta, nel Task 6 (l'ultimo). Versione target: **0.8.0+10**.
- Nessuna migrazione DB, nessuna modifica a `lib/data/db/db_helper.dart`.
- Modifiche chirurgiche: non toccare file fuori da quelli elencati in ogni task.
- **Commit:** l'utente ha autorizzato un commit per task, direttamente su `main` (2026-07-21). Esegui gli step "Commit". Nessun push: quello resta su richiesta esplicita. Mai `--force`, `reset --hard` o `--no-verify`.
- Comando test mirato: `flutter test test/<file>.dart --plain-name "<nome test>"`.

---

## File Structure

| File | Responsabilità | Azione |
|---|---|---|
| `lib/core/utils/formatters.dart` | formattazione importi/date it_IT | +`formatValuta`, `formatEur` diventa un caso particolare |
| `lib/data/repositories/spesa_repository.dart` | CRUD + aggregazioni spese | +`totaliPerCategoria` |
| `lib/ui/trasferte/trasferta_detail_controller.dart` | stato schermata dettaglio | +`valutaUnica`, campo categorie unificato |
| `lib/ui/trasferte/trasferta_detail_screen.dart` | UI dettaglio (`_TotalsHeader`, `_CategoryTotals`) | render per valuta |
| `lib/ui/trasferte/trasferte_list_controller.dart` | stato lista trasferte | +`totaliPerValuta` per item, +`countSenzaEurTotale` |
| `lib/ui/shared/widgets/trip_card.dart` | card della lista | render per valuta |
| `lib/ui/trasferte/trasferte_list_screen.dart` | UI lista (`_TotalHeader`) | nota spese non convertite |

---

### Task 1: Formatter per valuta

**Files:**
- Modify: `lib/core/utils/formatters.dart:5-11`
- Test: `test/formatters_test.dart`

**Interfaces:**
- Consumes: `Currency` da `lib/core/constants/currencies.dart` (`code`, `symbol`, `decimalDigits`, `static Currency? fromCode(String)`).
- Produces: `String formatValuta(double value, String codeIso)`. `String formatEur(double value)` resta invariato come firma.

- [ ] **Step 1: Write the failing test**

In coda a `test/formatters_test.dart`, dentro il `main()` esistente:

```dart
  group('formatValuta', () {
    test('uses the currency symbol and its decimal digits', () {
      expect(formatValuta(45320, 'JPY'), '¥ 45.320'); // 0 decimali
      expect(formatValuta(12.5, 'EUR'), '€ 12,50');
      expect(formatValuta(1.5, 'KWD'), 'د.ك 1,500'); // 3 decimali
    });

    test('unknown ISO code falls back to the code itself, 2 decimals', () {
      expect(formatValuta(10, 'XXX'), 'XXX 10,00');
    });

    test('formatEur stays the EUR case of formatValuta', () {
      expect(formatEur(345.5), '€ 345,50');
    });
  });
```

Verifica che `import 'package:nota_spese/core/utils/formatters.dart';` sia già in cima al file (c'è).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/formatters_test.dart --plain-name "uses the currency symbol"`
Expected: FAIL — `The function 'formatValuta' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

In `lib/core/utils/formatters.dart`, aggiungi l'import e sostituisci `formatEur`:

```dart
import 'package:intl/intl.dart';

import '../constants/currencies.dart';
```

```dart
/// Amount with the ISO currency symbol and that currency's decimal digits
/// (JPY has none, KWD has three). Unknown code → the code itself as prefix.
String formatValuta(double value, String codeIso) {
  final currency = Currency.fromCode(codeIso);
  if (currency == null) return '$codeIso ${formatImporto(value)}';
  return '${currency.symbol} '
      '${formatImporto(value, decimalDigits: currency.decimalDigits)}';
}

String formatEur(double value) => formatValuta(value, 'EUR');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/formatters_test.dart`
Expected: PASS, tutti i test del file (i vecchi su `formatEur` inclusi).

- [ ] **Step 5: Commit** *(solo se autorizzato — vedi Global Constraints)*

```bash
git add lib/core/utils/formatters.dart test/formatters_test.dart
git commit -m "feat: formatValuta renders amounts in their original currency"
```

---

### Task 2: Totali per categoria in valuta originale

**Files:**
- Modify: `lib/data/repositories/spesa_repository.dart:104-116` (aggiunta dopo `totaliEurPerCategoria`)
- Test: `test/repositories_test.dart` (gruppo `SpesaRepository`, accanto al test `totaliEurPerCategoria` a riga ~240)

**Interfaces:**
- Consumes: `DbHelper.database`, `Categoria` da `lib/core/constants/categories.dart`.
- Produces: `Future<Map<Categoria, double>> SpesaRepository.totaliPerCategoria(int trasfertaId)` — somma di `importo` (valuta originale) per categoria, tutte le spese incluse (nessun filtro su `importo_eur`).

- [ ] **Step 1: Write the failing test**

Subito dopo il test `totaliEurPerCategoria groups by category, skips unconverted`:

```dart
    test('totaliPerCategoria sums importo in original currency, no EUR filter',
        () async {
      await repo.insert(spesa(categoria: Categoria.cena, importo: 3000, valuta: 'JPY'));
      await repo.insert(spesa(categoria: Categoria.cena, importo: 1500, valuta: 'JPY'));
      await repo.insert(spesa(categoria: Categoria.taxi, importo: 800, valuta: 'JPY'));

      final totali = await repo.totaliPerCategoria(trasfertaId);

      expect(totali, {Categoria.cena: 4500.0, Categoria.taxi: 800.0});
    });

    test('totaliPerCategoria is empty for a trasferta without spese', () async {
      expect(await repo.totaliPerCategoria(trasfertaId), isEmpty);
    });
```

L'helper `spesa({categoria, importo, valuta, importoEur, data})` esiste già in quel file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories_test.dart --plain-name "totaliPerCategoria"`
Expected: FAIL — `The method 'totaliPerCategoria' isn't defined for the type 'SpesaRepository'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/data/repositories/spesa_repository.dart`, dopo `totaliEurPerCategoria`:

```dart
  /// Sum of `importo` (original currency) grouped by categoria. Meaningful
  /// only when the trasferta has a single valuta — callers check
  /// [totaliPerValuta] first and fall back to [totaliEurPerCategoria].
  Future<Map<Categoria, double>> totaliPerCategoria(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT categoria, SUM(importo) AS totale FROM spese '
        'WHERE trasferta_id = ? GROUP BY categoria',
        [trasfertaId]);
    return {
      for (final row in rows)
        Categoria.values.byName(row['categoria'] as String):
            (row['totale'] as num).toDouble(),
    };
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/repositories_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** *(solo se autorizzato)*

```bash
git add lib/data/repositories/spesa_repository.dart test/repositories_test.dart
git commit -m "feat: per-category totals in the original currency"
```

---

### Task 3: Dettaglio — controller e UI dei totali

Controller e schermata cambiano insieme: il campo `totaliEurPerCategoria`
sparisce, quindi separarli lascerebbe il progetto non compilabile a metà.

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart:28-57`
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart:382-385` (uso del campo categorie), `:420-468` (`_TotalsHeader`), `:471-530` (`_CategoryTotals`)
- Test: `test/trasferta_detail_controller_test.dart`, `test/trasferta_detail_screen_test.dart`

**Interfaces:**
- Consumes: `SpesaRepository.totaliPerValuta`, `.totaliPerCategoria` (Task 2), `.totaliEurPerCategoria`; `formatValuta` (Task 1).
- Produces:
  - `String? get valutaUnica` — codice ISO se `totaliPerValuta` ha esattamente una chiave, altrimenti `null`.
  - `Map<Categoria, double> totaliPerCategoria` — **sostituisce** il campo `totaliEurPerCategoria`; contiene importi in `valutaUnica` se non nullo, altrimenti importi EUR.
  - `String get valutaCategorie` → `valutaUnica ?? 'EUR'`, usato dalla UI per formattare ed etichettare.

- [ ] **Step 1: Write the failing test**

In `test/trasferta_detail_controller_test.dart`, dentro il `main()`:

```dart
  test('single currency: valutaUnica set, categorie in that currency',
      () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 20),
    ));

    final c = controller();
    await c.load();

    expect(c.valutaUnica, 'JPY');
    expect(c.valutaCategorie, 'JPY');
    expect(c.totaliPerCategoria, {Categoria.cena: 3000.0});
  });

  test('two currencies: valutaUnica null, categorie fall back to EUR',
      () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      importoEur: 18,
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

    final c = controller();
    await c.load();

    expect(c.valutaUnica, isNull);
    expect(c.valutaCategorie, 'EUR');
    expect(c.totaliPerCategoria, {Categoria.cena: 18.0, Categoria.taxi: 20.0});
  });

  test('no spese: valutaUnica null and categorie empty', () async {
    final c = controller();
    await c.load();

    expect(c.valutaUnica, isNull);
    expect(c.totaliPerCategoria, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/trasferta_detail_controller_test.dart --plain-name "single currency"`
Expected: FAIL — `The getter 'valutaUnica' isn't defined for the type 'TrasfertaDetailController'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/ui/trasferte/trasferta_detail_controller.dart` sostituisci la dichiarazione del campo:

```dart
  Map<String, double> totaliPerValuta = {};
  Map<Categoria, double> totaliPerCategoria = {};
```

(la riga `Map<Categoria, double> totaliEurPerCategoria = {};` sparisce)

e aggiungi, sotto i campi:

```dart
  /// The trip's only currency, or null when spese mix currencies (or there
  /// are none): totals in different currencies must never be summed.
  String? get valutaUnica =>
      totaliPerValuta.length == 1 ? totaliPerValuta.keys.first : null;

  /// Currency the per-category totals are expressed in.
  String get valutaCategorie => valutaUnica ?? 'EUR';
```

In `load()` sostituisci le due righe delle categorie:

```dart
    totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);
    totaliPerCategoria = valutaUnica == null
        ? await _spesaRepository.totaliEurPerCategoria(trasfertaId)
        : await _spesaRepository.totaliPerCategoria(trasfertaId);
```

Nota d'ordine: `totaliPerValuta` va assegnato **prima**, perché `valutaUnica` lo legge.

- [ ] **Step 4: Run controller tests to verify they pass**

Run: `flutter test test/trasferta_detail_controller_test.dart`
Expected: PASS.
`flutter analyze` è ancora rosso su `trasferta_detail_screen.dart` (usa il campo appena rimosso): lo sistemano gli step 5-8 di questo stesso task. Non committare qui.

- [ ] **Step 5: Write the failing widget test**

In `test/trasferta_detail_screen_test.dart`, dopo il test `shows empty state when no spese`:

```dart
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

    expect(find.text('¥ 3.000'), findsOneWidget);
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

    expect(find.text('¥ 3.000'), findsOneWidget);
    expect(find.textContaining('≈ €'), findsNothing);
    expect(find.text('€ 0,00'), findsNothing);
    expect(find.text('1 spese senza conversione EUR'), findsOneWidget);
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
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/trasferta_detail_screen_test.dart --plain-name "header shows the original currency"`
Expected: FAIL — compilazione KO su `totaliEurPerCategoria` (rimosso allo step 3) oppure, una volta compilato, `€ 17,90` al posto di `¥ 3.000`.

- [ ] **Step 7: Write minimal implementation**

3a. Nel `body` (riga ~382) sostituisci le due referenze al campo rimosso:

```dart
                    if (controller.totaliPerCategoria.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CategoryTotals(
                        totali: controller.totaliPerCategoria,
                        valuta: controller.valutaCategorie,
                      ),
                    ],
```

3b. Sostituisci il `child: Column(...)` di `_TotalsHeader` con:

```dart
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totale trasferta',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            for (final e in _righeValuta())
              Text(
                formatValuta(e.value, e.key),
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: amountFontFeatures,
                  fontWeight: FontWeight.w800,
                ),
              ),
            // The EUR line is a hint, not the total: hidden when there is
            // nothing converted (would read as a zeroed trip) and when EUR
            // is already the only currency shown above.
            if (controller.totaleEur > 0 && controller.valutaUnica != 'EUR')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '≈ ${formatEur(controller.totaleEur)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            if (controller.countSenzaEur > 0)
              Text(
                '${controller.countSenzaEur} spese senza conversione EUR',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
```

3c. Aggiungi a `_TotalsHeader` il metodo che ordina le righe (valuta della trasferta per prima, poi importo decrescente) e copre il caso "nessuna spesa":

```dart
  /// Trip currency first, then the others by descending amount. With no
  /// spese at all, a single zero row in the trip's own currency.
  List<MapEntry<String, double>> _righeValuta() {
    final totali = controller.totaliPerValuta;
    final valutaTrasferta = controller.trasferta?.valutaDefault ?? 'EUR';
    if (totali.isEmpty) return [MapEntry(valutaTrasferta, 0)];
    final entries = totali.entries.toList()
      ..sort((a, b) {
        if (a.key == valutaTrasferta) return -1;
        if (b.key == valutaTrasferta) return 1;
        return b.value.compareTo(a.value);
      });
    return entries;
  }
```

3d. In `_CategoryTotals` aggiungi il parametro valuta e usalo in etichetta e importi:

```dart
class _CategoryTotals extends StatelessWidget {
  const _CategoryTotals({required this.totali, required this.valuta});

  final Map<Categoria, double> totali;
  final String valuta;
```

etichetta:

```dart
            Text('Totali per categoria ($valuta)',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
```

importo di riga (sostituisce `formatEur(e.value)`):

```dart
                      formatValuta(e.value, valuta),
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/trasferta_detail_screen_test.dart test/trasferta_detail_controller_test.dart`
Expected: PASS, inclusi i test preesistenti (`shows empty state when no spese` continua a trovare `€ 0,00` perché la trasferta fixture ha `valutaDefault` EUR; `manual expense flow` continua a trovare `Totali per categoria (EUR)` perché la sua unica valuta è EUR).

Poi: `flutter analyze` → zero issue.

- [ ] **Step 9: Commit** *(solo se autorizzato)*

```bash
git add lib/ui/trasferte/trasferta_detail_controller.dart lib/ui/trasferte/trasferta_detail_screen.dart test/trasferta_detail_controller_test.dart test/trasferta_detail_screen_test.dart
git commit -m "feat: trip detail leads with original-currency totals"
```

---

### Task 4: Lista — controller e card

Stesso motivo del Task 3: `TrasfertaListItem` guadagna un parametro
obbligatorio, quindi la card e i suoi test vanno aggiornati nello stesso task.

**Files:**
- Modify: `lib/ui/trasferte/trasferte_list_controller.dart:8-53`
- Modify: `lib/ui/shared/widgets/trip_card.dart:95-101`
- Test: `test/trasferte_list_controller_test.dart`, `test/trip_card_test.dart`

**Interfaces:**
- Consumes: `SpesaRepository.totaliPerValuta`, `.countSenzaEur`, `.totaleEur`, `.countByTrasferta`; `formatValuta`, `formatEur` (Task 1).
- Produces:
  - `TrasfertaListItem({required Trasferta trasferta, required int numSpese, required double totaleEur, required Map<String, double> totaliPerValuta})` — nuovo parametro **obbligatorio** in coda.
  - `int TrasferteListController.countSenzaEurTotale`.

- [ ] **Step 1: Write the failing test**

In `test/trasferte_list_controller_test.dart`, dentro il `main()`:

```dart
  test('items carry per-currency totals and unconverted spese are counted',
      () async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 16, 20),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.taxi,
      importo: 20,
      valuta: 'EUR',
      importoEur: 20,
      createdAt: DateTime(2026, 7, 16, 21),
    ));

    await controller.load();

    expect(controller.items.single.totaliPerValuta,
        {'JPY': 3000.0, 'EUR': 20.0});
    expect(controller.totaleComplessivoEur, 20);
    expect(controller.countSenzaEurTotale, 1);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/trasferte_list_controller_test.dart --plain-name "items carry per-currency totals"`
Expected: FAIL — `The getter 'totaliPerValuta' isn't defined for the type 'TrasfertaListItem'`.

- [ ] **Step 3: Write minimal implementation**

`TrasfertaListItem`:

```dart
class TrasfertaListItem {
  const TrasfertaListItem({
    required this.trasferta,
    required this.numSpese,
    required this.totaleEur,
    required this.totaliPerValuta,
  });

  final Trasferta trasferta;
  final int numSpese;
  final double totaleEur;

  /// Sums in the currencies actually used by this trip's spese.
  final Map<String, double> totaliPerValuta;
}
```

Campo del controller, accanto a `totaleComplessivoEur`:

```dart
  int countSenzaEurTotale = 0;
```

Corpo di `load()`:

```dart
    final list = <TrasfertaListItem>[];
    var totale = 0.0;
    var senzaEur = 0;
    for (final t in trasferte) {
      final numSpese = await _spesaRepository.countByTrasferta(t.id!);
      final totaleEur = await _spesaRepository.totaleEur(t.id!);
      final totaliPerValuta = await _spesaRepository.totaliPerValuta(t.id!);
      list.add(TrasfertaListItem(
        trasferta: t,
        numSpese: numSpese,
        totaleEur: totaleEur,
        totaliPerValuta: totaliPerValuta,
      ));
      totale += totaleEur;
      senzaEur += await _spesaRepository.countSenzaEur(t.id!);
    }
    items = list;
    totaleComplessivoEur = totale;
    countSenzaEurTotale = senzaEur;
```

- [ ] **Step 4: Run controller tests to verify they pass**

Run: `flutter test test/trasferte_list_controller_test.dart`
Expected: PASS.
`flutter analyze` è ancora rosso su `trip_card.dart` e `trip_card_test.dart` (parametro obbligatorio mancante): lo sistemano gli step 5-8. Non committare qui.

- [ ] **Step 5: Write the failing widget test**

Aggiorna l'helper `item(...)` in cima a `test/trip_card_test.dart` — serve il nuovo parametro obbligatorio — e aggiungi due test:

```dart
  TrasfertaListItem item({
    bool archiviata = false,
    Map<String, double> totaliPerValuta = const {'JPY': 45320.0},
    double totaleEur = 345.5,
  }) =>
      TrasfertaListItem(
        trasferta: Trasferta(
          id: 1,
          nome: 'Tokyo Q3',
          luogo: 'Tokyo',
          dataInizio: DateTime(2026, 7, 10),
          dataFine: DateTime(2026, 7, 15),
          valutaDefault: 'JPY',
          archiviata: archiviata,
          createdAt: DateTime(2026, 7, 9),
        ),
        numSpese: 12,
        totaleEur: totaleEur,
        totaliPerValuta: totaliPerValuta,
      );
```

Nel test esistente `shows trip data`, sostituisci `expect(find.text('€ 345,50'), findsOneWidget);` con:

```dart
    expect(find.text('¥ 45.320'), findsOneWidget);
    expect(find.text('≈ € 345,50'), findsOneWidget);
```

E in coda al file:

```dart
  testWidgets('without conversion the card shows no euro line', (tester) async {
    await pump(tester, TripCard(item: item(totaleEur: 0)));

    expect(find.text('¥ 45.320'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
  });

  testWidgets('EUR-only trip shows no redundant euro hint', (tester) async {
    await pump(
        tester,
        TripCard(
            item: item(
                totaliPerValuta: const {'EUR': 40.0}, totaleEur: 40)));

    expect(find.text('€ 40,00'), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);
  });
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/trip_card_test.dart`
Expected: FAIL — `€ 345,50` renderizzato al posto di `¥ 45.320`.

- [ ] **Step 7: Write minimal implementation**

In `trip_card.dart` sostituisci il `Text(formatEur(item.totaleEur), ...)` con:

```dart
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in _righeValuta())
                    Text(
                      formatValuta(e.value, e.key),
                      style: textTheme.titleMedium?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  // Same rule as the detail header: the EUR hint disappears
                  // when nothing is converted or when EUR is already shown.
                  if (item.totaleEur > 0 &&
                      !(item.totaliPerValuta.length == 1 &&
                          item.totaliPerValuta.containsKey('EUR')))
                    Text(
                      '≈ ${formatEur(item.totaleEur)}',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
```

e aggiungi il metodo alla classe `TripCard`:

```dart
  /// Trip currency first, then the others by descending amount; a zero row
  /// in the trip currency when there are no spese yet.
  List<MapEntry<String, double>> _righeValuta() {
    final valutaTrasferta = item.trasferta.valutaDefault;
    if (item.totaliPerValuta.isEmpty) return [MapEntry(valutaTrasferta, 0)];
    return item.totaliPerValuta.entries.toList()
      ..sort((a, b) {
        if (a.key == valutaTrasferta) return -1;
        if (b.key == valutaTrasferta) return 1;
        return b.value.compareTo(a.value);
      });
  }
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/trip_card_test.dart test/trasferte_list_controller_test.dart test/trasferte_list_screen_test.dart`
Expected: PASS. Se `trasferte_list_screen_test.dart` costruisce `TrasfertaListItem` a mano, aggiungi lì `totaliPerValuta: const {}`.

Poi: `flutter analyze` → zero issue.

- [ ] **Step 9: Commit** *(solo se autorizzato)*

```bash
git add lib/ui/trasferte/trasferte_list_controller.dart lib/ui/shared/widgets/trip_card.dart test/trasferte_list_controller_test.dart test/trip_card_test.dart
git commit -m "feat: trip list leads with original-currency totals"
```

---

### Task 5: Nota sulle spese non convertite nel totale complessivo

**Files:**
- Modify: `lib/ui/trasferte/trasferte_list_screen.dart:128`, `:149-178` (`_TotalHeader`)
- Test: `test/trasferte_list_screen_test.dart`

**Interfaces:**
- Consumes: `TrasferteListController.totaleComplessivoEur`, `.countSenzaEurTotale` (Task 4).
- Produces: nessuna API nuova. `_TotalHeader` passa da `({required double totale})` a `({required double totale, required int senzaEur})`.

- [ ] **Step 1: Write the failing test**

`test/trasferte_list_screen_test.dart` non importa ancora i modelli spesa: aggiungi in cima, in ordine alfabetico tra gli import esistenti,

```dart
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
```

poi in coda al `main()` (usa l'helper `trasferta(...)` e la `pump(...)` già definiti nel file, righe 45-76):

```dart
  testWidgets('overall total warns about spese without conversion',
      (tester) async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 16, 20),
    ));

    await pump(tester);

    expect(find.text('Totale complessivo'), findsOneWidget);
    expect(find.text('esclude 1 spese senza conversione'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/trasferte_list_screen_test.dart --plain-name "warns about spese without conversion"`
Expected: FAIL — testo non trovato.

- [ ] **Step 3: Write minimal implementation**

Chiamata (riga ~128):

```dart
                _TotalHeader(
                  totale: controller.totaleComplessivoEur,
                  senzaEur: controller.countSenzaEurTotale,
                ),
```

Widget:

```dart
class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.totale, required this.senzaEur});

  final double totale;
  final int senzaEur;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Totale complessivo',
                    style: textTheme.labelLarge
                        ?.copyWith(color: AppColors.textSecondary)),
                Text(
                  formatEur(totale),
                  style: textTheme.titleLarge?.copyWith(
                    fontFeatures: amountFontFeatures,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            // Cross-trip sums only work in EUR: say what is missing instead
            // of letting a low total look wrong.
            if (senzaEur > 0)
              Text(
                'esclude $senzaEur spese senza conversione',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trasferte_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit** *(solo se autorizzato)*

```bash
git add lib/ui/trasferte/trasferte_list_screen.dart test/trasferte_list_screen_test.dart
git commit -m "feat: overall total states how many spese it excludes"
```

---

### Task 6: Verifica finale, versione, ToDo

**Files:**
- Modify: `lib/version.dart:3`, `pubspec.yaml:20`, `ToDo.md` (sezione "Bug rilevati" della fase 6b)

**Interfaces:**
- Consumes: tutti i task precedenti.
- Produces: nessuna API.

- [ ] **Step 1: Suite completa**

Run: `flutter test`
Expected: PASS, nessun test fallito.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Bump versione**

`lib/version.dart`:

```dart
const String appVersion = '0.8.0';
```

`pubspec.yaml`:

```yaml
version: 0.8.0+10
```

- [ ] **Step 4: Aggiorna `ToDo.md`**

Nella sezione `### Bug rilevati` della fase 6b aggiungi:

```markdown
- [x] **BUG-03 — Importo primario in EUR invece che nella valuta originale** (2026-07-21). L'app dava rilievo a un dato derivato e opzionale (`importo_eur`): senza conversione tutte le schermate mostravano `€ 0,00` pur avendo spese registrate. Fix: totali primari per valuta originale in header dettaglio e card lista, EUR come riga secondaria nascosta quando manca o quando è già l'unica valuta, categorie in valuta originale se la trasferta ne ha una sola, nota `esclude N spese senza conversione` sul totale complessivo. Spec `docs/superpowers/specs/2026-07-21-importo-primario-valuta-originale-design.md`. v0.8.0
```

- [ ] **Step 5: Rerun della suite dopo il bump**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 6: Commit** *(solo se autorizzato)*

```bash
git add lib/version.dart pubspec.yaml ToDo.md
git commit -m "chore: bump to 0.8.0, original-currency totals"
```

---

## Verifica di fase (CLAUDE.md)

- [ ] `flutter analyze` → zero issue
- [ ] `flutter test` → verde
- [ ] Build su emulatore: **SKIP esplicito** — ambiente Android incompleto su questa macchina (JDK 11, piattaforme SDK assenti). La verifica reale avviene sull'APK della GitHub Action.
- [ ] Verifica manuale sul dispositivo: aprire una trasferta con spese in valuta estera non convertite e controllare che il totale mostri la valuta originale e non `€ 0,00`.
- [ ] `ToDo.md` aggiornato (Task 6)
