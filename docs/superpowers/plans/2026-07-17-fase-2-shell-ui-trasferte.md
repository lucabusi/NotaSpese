# Fase 2 — Shell UI + CRUD Trasferte Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prima UI navigabile: NavigationBar 3 tab, lista trasferte attive con totali, form crea/modifica, dettaglio scheletro, archivia/ripristina/elimina con conferma, tab Archivio, controller ChangeNotifier su repository fase 1.

**Architecture:** UI → controller (`ChangeNotifier` + `ListenableBuilder`) → repository. Composizione manuale in `main.dart`. Un controller per lista (riusato da tab Trasferte e Archivio via flag) + un controller per dettaglio. Screen e controller in file separati.

**Tech Stack:** Flutter Material 3, tema esistente `app_theme.dart`, `intl` (formattazione), repository fase 1, `sqflite_common_ffi` nei test (unit + widget).

## Global Constraints

- UI in italiano; codice/identificatori inglese, nomi dominio da spec in italiano.
- Naming: screen = `<feature>_screen.dart`, controller = `<feature>_controller.dart`; widget riusati in `ui/shared/widgets/`.
- Controller non toccano mai `sqflite`/filesystem: solo repository.
- Ogni azione distruttiva (elimina) → dialog di conferma esplicita.
- Design System: token da `AppColors`/`AppRadius`, importi con `amountFontFeatures` (tabular figures).
- **NIENTE commit automatici** (CLAUDE.md globale): commit solo su richiesta esplicita.
- Bump a fine fase: `pubspec.yaml` → `0.3.0+3`, `lib/version.dart` → `'0.3.0'`.
- Verifica fase: `flutter analyze` zero issue + `flutter test` verde; prova su emulatore = **SKIP esplicito** (gotcha ambiente in CLAUDE.md), compensata da widget test del flusso crea/modifica/archivia/elimina.
- Currency picker searchable è fase 3: nel form trasferta si usa `DropdownMenu` semplice (frequenti in cima), da sostituire in fase 3.

---

### Task 1: Formatters + SpesaRepository.countByTrasferta

**Files:**
- Create: `lib/core/utils/formatters.dart`
- Modify: `lib/data/repositories/spesa_repository.dart` (aggiungere `countByTrasferta`)
- Test: `test/formatters_test.dart`, `test/repositories_test.dart` (test count nel gruppo SpesaRepository)
- Delete: `lib/core/utils/.gitkeep`

**Interfaces:**
- Produces: `String formatImporto(double value, {int decimalDigits = 2})` (it_IT: `1.234,56`); `String formatEur(double value)` (`€ 1.234,56`); `String formatDate(DateTime d)` (`dd/MM/yyyy`); `String formatDateRange(DateTime start, DateTime? end)` (`10/07/2026 – 15/07/2026`, end null → `10/07/2026 – in corso`); `SpesaRepository.countByTrasferta(int trasfertaId) → Future<int>`.
- Nota: date con pattern fisso `dd/MM/yyyy` (niente `initializeDateFormatting`); importi via `NumberFormat` it_IT (dati numerici inclusi in intl senza init).

- [ ] **Step 1: Write the failing tests**

```dart
// test/formatters_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/utils/formatters.dart';

void main() {
  test('formatImporto uses it_IT separators', () {
    expect(formatImporto(1234.56), '1.234,56');
    expect(formatImporto(0.5), '0,50');
    expect(formatImporto(3000, decimalDigits: 0), '3.000');
  });

  test('formatEur prefixes euro symbol', () {
    expect(formatEur(1234.56), '€ 1.234,56');
  });

  test('formatDate is dd/MM/yyyy', () {
    expect(formatDate(DateTime(2026, 7, 5)), '05/07/2026');
  });

  test('formatDateRange handles open-ended trips', () {
    expect(formatDateRange(DateTime(2026, 7, 10), DateTime(2026, 7, 15)),
        '10/07/2026 – 15/07/2026');
    expect(formatDateRange(DateTime(2026, 7, 10), null),
        '10/07/2026 – in corso');
  });
}
```

In `test/repositories_test.dart`, gruppo SpesaRepository:

```dart
    test('countByTrasferta counts only that trip', () async {
      await repo.insert(spesa());
      await repo.insert(spesa());
      expect(await repo.countByTrasferta(trasfertaId), 2);
      expect(await repo.countByTrasferta(trasfertaId + 999), 0);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/formatters_test.dart test/repositories_test.dart`
Expected: FAIL (file/metodo inesistenti).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/formatters.dart
import 'package:intl/intl.dart';

/// it_IT amount/date formatting. Dates use a fixed dd/MM/yyyy pattern so
/// no locale-data initialization is needed in tests or at startup.
String formatImporto(double value, {int decimalDigits = 2}) =>
    NumberFormat.decimalPatternDigits(locale: 'it_IT', decimalDigits: decimalDigits)
        .format(value);

String formatEur(double value) => '€ ${formatImporto(value)}';

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String formatDateRange(DateTime start, DateTime? end) =>
    '${formatDate(start)} – ${end == null ? 'in corso' : formatDate(end)}';
```

In `spesa_repository.dart`:

```dart
  Future<int> countByTrasferta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM spese WHERE trasferta_id = ?',
        [trasfertaId]);
    return rows.first['n'] as int;
  }
```

- [ ] **Step 4: Delete `lib/core/utils/.gitkeep`; run tests**

Run: `flutter test test/formatters_test.dart test/repositories_test.dart`
Expected: PASS.

---

### Task 2: TrasferteListController

**Files:**
- Create: `lib/ui/trasferte/trasferte_list_controller.dart`
- Test: `test/trasferte_list_controller_test.dart`
- Delete: `lib/ui/trasferte/.gitkeep`

**Interfaces:**
- Consumes: `TrasfertaRepository`, `SpesaRepository`, `Trasferta`.
- Produces:
  - `class TrasfertaListItem { final Trasferta trasferta; final int numSpese; final double totaleEur; }`
  - `class TrasferteListController extends ChangeNotifier` con ctor `(TrasfertaRepository, SpesaRepository, {required bool archiviate})`; stato `bool loading`, `List<TrasfertaListItem> items`, `double totaleComplessivoEur`; metodi `Future<void> load()`, `Future<void> create(Trasferta)`, `Future<void> updateTrasferta(Trasferta)`, `Future<void> setArchiviata(int id, bool archiviata)`, `Future<void> elimina(int id)` — ogni mutazione ricarica e `notifyListeners()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/trasferte_list_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late TrasferteListController controller;

  Trasferta trasferta({String nome = 'Trip', bool archiviata = false}) =>
      Trasferta(
        nome: nome,
        dataInizio: DateTime(2026, 7, 15),
        archiviata: archiviata,
        createdAt: DateTime(2026, 7, 15, 8),
      );

  setUp(() {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    controller =
        TrasferteListController(trasfertaRepo, spesaRepo, archiviate: false);
  });

  tearDown(() => dbHelper.close());

  test('load exposes active trips with counts and totals', () async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 30,
      valuta: 'EUR',
      importoEur: 30,
      createdAt: DateTime(2026, 7, 16, 21),
    ));

    await controller.load();

    expect(controller.items.length, 1);
    expect(controller.items.first.trasferta.nome, 'Tokyo');
    expect(controller.items.first.numSpese, 1);
    expect(controller.items.first.totaleEur, 30);
    expect(controller.totaleComplessivoEur, 30);
  });

  test('archiviate: true lists only archived trips', () async {
    await trasfertaRepo.insert(trasferta(nome: 'Active'));
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    final archived = TrasferteListController(trasfertaRepo, spesaRepo,
        archiviate: true);

    await archived.load();

    expect(archived.items.map((i) => i.trasferta.nome).toList(), ['Old']);
  });

  test('create/updateTrasferta/setArchiviata/elimina reload the list',
      () async {
    await controller.create(trasferta(nome: 'A'));
    expect(controller.items.length, 1);

    final t = controller.items.first.trasferta;
    await controller.updateTrasferta(Trasferta(
      id: t.id,
      nome: 'B',
      dataInizio: t.dataInizio,
      createdAt: t.createdAt,
    ));
    expect(controller.items.first.trasferta.nome, 'B');

    await controller.setArchiviata(t.id!, true);
    expect(controller.items, isEmpty);

    await controller.setArchiviata(t.id!, false);
    await controller.elimina(t.id!);
    expect(controller.items, isEmpty);
    expect(await trasfertaRepo.getById(t.id!), isNull);
  });

  test('notifies listeners on load', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.load();
    expect(notified, greaterThanOrEqualTo(1));
  });
}
```

(aggiungere `import 'dart:io';` in cima per `Directory`)

- [ ] **Step 2: Run test to verify it fails** — `flutter test test/trasferte_list_controller_test.dart` → FAIL.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/trasferte/trasferte_list_controller.dart
import 'package:flutter/foundation.dart';

import '../../data/models/trasferta.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';

/// Row data for the trip list: trip + per-trip aggregates.
class TrasfertaListItem {
  const TrasfertaListItem({
    required this.trasferta,
    required this.numSpese,
    required this.totaleEur,
  });

  final Trasferta trasferta;
  final int numSpese;
  final double totaleEur;
}

/// Backs both the "Trasferte attive" and "Archivio" tabs (flag [archiviate]).
/// Every mutation reloads from the repositories and notifies.
class TrasferteListController extends ChangeNotifier {
  TrasferteListController(this._trasfertaRepository, this._spesaRepository,
      {required this.archiviate});

  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;
  final bool archiviate;

  bool loading = false;
  List<TrasfertaListItem> items = [];
  double totaleComplessivoEur = 0;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final trasferte = archiviate
        ? await _trasfertaRepository.getArchiviate()
        : await _trasfertaRepository.getAttive();
    final list = <TrasfertaListItem>[];
    var totale = 0.0;
    for (final t in trasferte) {
      final numSpese = await _spesaRepository.countByTrasferta(t.id!);
      final totaleEur = await _spesaRepository.totaleEur(t.id!);
      list.add(TrasfertaListItem(
          trasferta: t, numSpese: numSpese, totaleEur: totaleEur));
      totale += totaleEur;
    }
    items = list;
    totaleComplessivoEur = totale;
    loading = false;
    notifyListeners();
  }

  Future<void> create(Trasferta trasferta) async {
    await _trasfertaRepository.insert(trasferta);
    await load();
  }

  Future<void> updateTrasferta(Trasferta trasferta) async {
    await _trasfertaRepository.update(trasferta);
    await load();
  }

  Future<void> setArchiviata(int id, bool archiviata) async {
    await _trasfertaRepository.setArchiviata(id, archiviata);
    await load();
  }

  Future<void> elimina(int id) async {
    await _trasfertaRepository.delete(id);
    await load();
  }
}
```

- [ ] **Step 4: Delete `lib/ui/trasferte/.gitkeep`; run test** → PASS.

---

### Task 3: TrasfertaDetailController

**Files:**
- Create: `lib/ui/trasferte/trasferta_detail_controller.dart`
- Test: `test/trasferta_detail_controller_test.dart`

**Interfaces:**
- Consumes: `TrasfertaRepository`, `SpesaRepository`.
- Produces: `class TrasfertaDetailController extends ChangeNotifier` con ctor `(int trasfertaId, TrasfertaRepository, SpesaRepository)`; stato `Trasferta? trasferta`, `Map<DateTime, List<Spesa>> speseByData`, `double totaleEur`, `int countSenzaEur`, `Map<String, double> totaliPerValuta`, `bool loading`; metodi `Future<void> load()`, `Future<void> setArchiviata(bool)`, `Future<void> elimina()`, `Future<void> updateTrasferta(Trasferta)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/trasferta_detail_controller_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late int trasfertaId;

  setUp(() async {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() => dbHelper.close());

  TrasfertaDetailController controller() =>
      TrasfertaDetailController(trasfertaId, trasfertaRepo, spesaRepo);

  test('load exposes trip, grouped spese and totals', () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
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

    expect(c.trasferta!.nome, 'Tokyo');
    expect(c.speseByData.keys.toList(),
        [DateTime(2026, 7, 12), DateTime(2026, 7, 11)]);
    expect(c.totaleEur, 20);
    expect(c.countSenzaEur, 1);
    expect(c.totaliPerValuta, {'JPY': 3000.0, 'EUR': 20.0});
  });

  test('setArchiviata and elimina act on the trip', () async {
    final c = controller();
    await c.load();

    await c.setArchiviata(true);
    expect(c.trasferta!.archiviata, isTrue);

    await c.elimina();
    expect(await trasfertaRepo.getById(trasfertaId), isNull);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/trasferte/trasferta_detail_controller.dart
import 'package:flutter/foundation.dart';

import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';

/// Detail screen state: the trip, its spese grouped by date and totals.
class TrasfertaDetailController extends ChangeNotifier {
  TrasfertaDetailController(
      this.trasfertaId, this._trasfertaRepository, this._spesaRepository);

  final int trasfertaId;
  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;

  bool loading = false;
  Trasferta? trasferta;
  Map<DateTime, List<Spesa>> speseByData = {};
  double totaleEur = 0;
  int countSenzaEur = 0;
  Map<String, double> totaliPerValuta = {};

  Future<void> load() async {
    loading = true;
    notifyListeners();
    trasferta = await _trasfertaRepository.getById(trasfertaId);
    speseByData =
        await _spesaRepository.getByTrasfertaGroupedByData(trasfertaId);
    totaleEur = await _spesaRepository.totaleEur(trasfertaId);
    countSenzaEur = await _spesaRepository.countSenzaEur(trasfertaId);
    totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);
    loading = false;
    notifyListeners();
  }

  Future<void> updateTrasferta(Trasferta aggiornata) async {
    await _trasfertaRepository.update(aggiornata);
    await load();
  }

  Future<void> setArchiviata(bool archiviata) async {
    await _trasfertaRepository.setArchiviata(trasfertaId, archiviata);
    await load();
  }

  Future<void> elimina() => _trasfertaRepository.delete(trasfertaId);
}
```

- [ ] **Step 4: Run test** → PASS.

---

### Task 4: TripCard widget

**Files:**
- Create: `lib/ui/shared/widgets/trip_card.dart`
- Test: `test/trip_card_test.dart`
- Delete: `lib/ui/shared/widgets/.gitkeep`

**Interfaces:**
- Consumes: `TrasfertaListItem` (Task 2), formatters (Task 1), `AppColors`.
- Produces: `class TripCard extends StatelessWidget` con ctor `({required TrasfertaListItem item, VoidCallback? onTap, VoidCallback? onArchivia, VoidCallback? onRipristina, VoidCallback? onElimina})`. Mostra: icona in cerchio `primaryContainer`, nome, luogo · range date, badge valuta default, "N spese", totale EUR (tabular), badge `ARCHIVIATA` se archiviata, `PopupMenuButton` (Archivia se attiva / Ripristina se archiviata, Elimina).

- [ ] **Step 1: Write the failing test**

```dart
// test/trip_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/ui/shared/widgets/trip_card.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';

void main() {
  TrasfertaListItem item({bool archiviata = false}) => TrasfertaListItem(
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
        totaleEur: 345.5,
      );

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('shows trip data', (tester) async {
    await pump(tester, TripCard(item: item()));

    expect(find.text('Tokyo Q3'), findsOneWidget);
    expect(find.textContaining('Tokyo ·'), findsOneWidget);
    expect(find.text('JPY'), findsOneWidget);
    expect(find.text('12 spese'), findsOneWidget);
    expect(find.text('€ 345,50'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsNothing);
  });

  testWidgets('shows ARCHIVIATA badge and Ripristina action when archived',
      (tester) async {
    await pump(tester, TripCard(item: item(archiviata: true)));

    expect(find.text('ARCHIVIATA'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<TripCardAction>));
    await tester.pumpAndSettle();
    expect(find.text('Ripristina'), findsOneWidget);
    expect(find.text('Archivia'), findsNothing);
    expect(find.text('Elimina'), findsOneWidget);
  });

  testWidgets('menu fires callbacks', (tester) async {
    var archived = false;
    await pump(tester,
        TripCard(item: item(), onArchivia: () => archived = true));

    await tester.tap(find.byType(PopupMenuButton<TripCardAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivia'));
    await tester.pumpAndSettle();

    expect(archived, isTrue);
  });

  testWidgets('onTap fires', (tester) async {
    var tapped = false;
    await pump(tester, TripCard(item: item(), onTap: () => tapped = true));
    await tester.tap(find.text('Tokyo Q3'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/shared/widgets/trip_card.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../trasferte/trasferte_list_controller.dart';

enum TripCardAction { archivia, ripristina, elimina }

/// Trip list card (mockup: icona, nome, date, badge valuta, n. spese, totale).
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.item,
    this.onTap,
    this.onArchivia,
    this.onRipristina,
    this.onElimina,
  });

  final TrasfertaListItem item;
  final VoidCallback? onTap;
  final VoidCallback? onArchivia;
  final VoidCallback? onRipristina;
  final VoidCallback? onElimina;

  @override
  Widget build(BuildContext context) {
    final t = item.trasferta;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [
      if (t.luogo != null && t.luogo!.isNotEmpty) t.luogo,
      formatDateRange(t.dataInizio, t.dataFine),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.primary,
                child: const Icon(Symbols.flight_takeoff),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.nome,
                              style: textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        _Badge(text: t.valutaDefault),
                        if (t.archiviata) ...[
                          const SizedBox(width: 6),
                          const _Badge(
                            text: 'ARCHIVIATA',
                            background: AppColors.archivioContainer,
                            foreground: AppColors.archivio,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text('${item.numSpese} spese',
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Text(
                formatEur(item.totaleEur),
                style: textTheme.titleMedium?.copyWith(
                  fontFeatures: amountFontFeatures,
                  fontWeight: FontWeight.w700,
                ),
              ),
              PopupMenuButton<TripCardAction>(
                onSelected: (action) => switch (action) {
                  TripCardAction.archivia => onArchivia?.call(),
                  TripCardAction.ripristina => onRipristina?.call(),
                  TripCardAction.elimina => onElimina?.call(),
                },
                itemBuilder: (context) => [
                  if (t.archiviata)
                    const PopupMenuItem(
                        value: TripCardAction.ripristina,
                        child: Text('Ripristina'))
                  else
                    const PopupMenuItem(
                        value: TripCardAction.archivia,
                        child: Text('Archivia')),
                  const PopupMenuItem(
                      value: TripCardAction.elimina, child: Text('Elimina')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    this.background = AppColors.primaryContainer,
    this.foreground = AppColors.primary,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}
```

- [ ] **Step 4: Delete `lib/ui/shared/widgets/.gitkeep`; run test** → PASS.

---

### Task 5: TrasfertaFormScreen (crea/modifica)

**Files:**
- Create: `lib/ui/trasferte/trasferta_form_screen.dart`
- Test: `test/trasferta_form_screen_test.dart`

**Interfaces:**
- Consumes: `Trasferta`, `Currency`, formatters.
- Produces: `class TrasfertaFormScreen extends StatefulWidget` con ctor `({Trasferta? initial, required Future<void> Function(Trasferta) onSave})`. Campi: nome (obbligatorio, validator), luogo, data inizio (date picker, default oggi), data fine (opzionale, clearable), valuta default (`DropdownMenu<Currency>` frequenti in cima), lingua default (`DropdownMenu<String?>`: Auto/it/en/ja/sr/de), note. Salva → costruisce `Trasferta` (conserva `id`/`createdAt`/`archiviata` di `initial` se presente) → `await onSave(t)` → `Navigator.pop`.

- [ ] **Step 1: Write the failing test**

```dart
// test/trasferta_form_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/ui/trasferte/trasferta_form_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {Trasferta? initial,
      required Future<void> Function(Trasferta) onSave}) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasfertaFormScreen(initial: initial, onSave: onSave),
    ));
  }

  testWidgets('rejects empty nome', (tester) async {
    Trasferta? saved;
    await pump(tester, onSave: (t) async => saved = t);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(find.text('Inserisci un nome'), findsOneWidget);
  });

  testWidgets('saves a new trip with defaults', (tester) async {
    Trasferta? saved;
    await pump(tester, onSave: (t) async => saved = t);

    await tester.enterText(
        find.byKey(const Key('campo-nome')), 'Tokyo Q3');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.nome, 'Tokyo Q3');
    expect(saved!.valutaDefault, 'EUR');
    expect(saved!.linguaDefault, isNull);
    expect(saved!.archiviata, isFalse);
  });

  testWidgets('editing keeps id and createdAt', (tester) async {
    final initial = Trasferta(
      id: 7,
      nome: 'Old name',
      dataInizio: DateTime(2026, 7, 1),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 6, 30, 12),
    );
    Trasferta? saved;
    await pump(tester, initial: initial, onSave: (t) async => saved = t);

    await tester.enterText(
        find.byKey(const Key('campo-nome')), 'New name');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved!.id, 7);
    expect(saved!.nome, 'New name');
    expect(saved!.valutaDefault, 'JPY');
    expect(saved!.createdAt, initial.createdAt);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/trasferte/trasferta_form_screen.dart
import 'package:flutter/material.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/trasferta.dart';

const _lingue = <String?, String>{
  null: 'Auto',
  'it': 'Italiano',
  'en': 'Inglese',
  'ja': 'Giapponese',
  'sr': 'Serbo',
  'de': 'Tedesco',
};

/// Create/edit trip form. [initial] == null → create; otherwise edit
/// (id, createdAt and archiviata are preserved).
class TrasfertaFormScreen extends StatefulWidget {
  const TrasfertaFormScreen({super.key, this.initial, required this.onSave});

  final Trasferta? initial;
  final Future<void> Function(Trasferta trasferta) onSave;

  @override
  State<TrasfertaFormScreen> createState() => _TrasfertaFormScreenState();
}

class _TrasfertaFormScreenState extends State<TrasfertaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome =
      TextEditingController(text: widget.initial?.nome ?? '');
  late final TextEditingController _luogo =
      TextEditingController(text: widget.initial?.luogo ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late DateTime _dataInizio = widget.initial?.dataInizio ?? DateTime.now();
  late DateTime? _dataFine = widget.initial?.dataFine;
  late String _valuta = widget.initial?.valutaDefault ?? 'EUR';
  late String? _lingua = widget.initial?.linguaDefault;

  @override
  void dispose() {
    _nome.dispose();
    _luogo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickData({required bool fine}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fine ? (_dataFine ?? _dataInizio) : _dataInizio,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (fine) {
        _dataFine = picked;
      } else {
        _dataInizio = picked;
      }
    });
  }

  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initial;
    final trasferta = Trasferta(
      id: initial?.id,
      nome: _nome.text.trim(),
      luogo: _luogo.text.trim().isEmpty ? null : _luogo.text.trim(),
      dataInizio: _dataInizio,
      dataFine: _dataFine,
      valutaDefault: _valuta,
      linguaDefault: _lingua,
      archiviata: initial?.archiviata ?? false,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: initial?.createdAt ?? DateTime.now(),
    );
    await widget.onSave(trasferta);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    // Frequent currencies first, then the rest (searchable picker → fase 3).
    final valute = [
      ...Currency.frequenti,
      ...Currency.values.where((c) => !c.frequente),
    ];

    return Scaffold(
      appBar: AppBar(
          title: Text(editing ? 'Modifica trasferta' : 'Nuova trasferta')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('campo-nome'),
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Inserisci un nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-luogo'),
              controller: _luogo,
              decoration: const InputDecoration(labelText: 'Luogo'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('campo-data-inizio'),
                    onPressed: () => _pickData(fine: false),
                    child: Text('Inizio: ${formatDate(_dataInizio)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('campo-data-fine'),
                    onPressed: () => _pickData(fine: true),
                    onLongPress: () => setState(() => _dataFine = null),
                    child: Text(_dataFine == null
                        ? 'Fine: —'
                        : 'Fine: ${formatDate(_dataFine!)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('campo-valuta'),
              initialValue: _valuta,
              decoration: const InputDecoration(labelText: 'Valuta default'),
              items: [
                for (final c in valute)
                  DropdownMenuItem(
                      value: c.code, child: Text('${c.code} — ${c.nome}')),
              ],
              onChanged: (v) => setState(() => _valuta = v ?? 'EUR'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('campo-lingua'),
              initialValue: _lingua,
              decoration: const InputDecoration(
                  labelText: 'Lingua default (hint OCR)'),
              items: [
                for (final e in _lingue.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _lingua = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salva,
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test** → PASS.

---

### Task 6: TrasfertaDetailScreen (scheletro)

**Files:**
- Create: `lib/ui/trasferte/trasferta_detail_screen.dart`
- Test: `test/trasferta_detail_screen_test.dart`

**Interfaces:**
- Consumes: `TrasfertaDetailController` (Task 3), `TrasfertaFormScreen` (Task 5), formatters, `Categoria`.
- Produces: `class TrasfertaDetailScreen extends StatefulWidget` con ctor `({required TrasfertaDetailController controller})` (il chiamante lo crea; lo screen chiama `load()` in `initState` e `dispose()` NON del controller — lo possiede il chiamante? No: per semplicità lo screen possiede il controller e lo dispone). Ctor definitivo: `({required TrasfertaDetailController controller})`, lo screen chiama `load()` in initState e `controller.dispose()` in dispose.
- Contenuto: AppBar con nome + menu (Modifica / Archivia|Ripristina / Elimina con conferma); header totale EUR + totali per valuta + nota spese senza EUR; lista spese raggruppate per data (in fase 2 tipicamente vuota → empty state "Nessuna spesa registrata"); FAB `+` → SnackBar "Inserimento spese: fase 3".
- `elimina`/`archivia` → dopo l'azione `Navigator.pop(context, true)` (il chiamante ricarica la lista).

- [ ] **Step 1: Write the failing test**

```dart
// test/trasferta_detail_screen_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late int trasfertaId;

  setUp(() async {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() => dbHelper.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasfertaDetailScreen(
        controller: TrasfertaDetailController(
            trasfertaId, trasfertaRepo, spesaRepo),
      ),
    ));
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
    expect(find.textContaining('3.000'), findsOneWidget);
    expect(find.text('Nessuna spesa registrata'), findsNothing);
  });

  testWidgets('FAB shows fase-3 placeholder snackbar', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.textContaining('fase 3'), findsOneWidget);
  });

  testWidgets('elimina asks confirmation and pops with result', (tester) async {
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
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/trasferte/trasferta_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/spesa.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_form_screen.dart';

enum DetailAction { modifica, archivia, ripristina, elimina }

/// Trip detail (fase 2 skeleton): totals header, spese list (usually
/// empty until fase 3), FAB placeholder. Pops `true` after archive/delete
/// so the list screen reloads.
class TrasfertaDetailScreen extends StatefulWidget {
  const TrasfertaDetailScreen({super.key, required this.controller});

  final TrasfertaDetailController controller;

  @override
  State<TrasfertaDetailScreen> createState() => _TrasfertaDetailScreenState();
}

class _TrasfertaDetailScreenState extends State<TrasfertaDetailScreen> {
  TrasfertaDetailController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _onAction(DetailAction action) async {
    switch (action) {
      case DetailAction.modifica:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TrasfertaFormScreen(
            initial: controller.trasferta,
            onSave: controller.updateTrasferta,
          ),
        ));
      case DetailAction.archivia:
        await controller.setArchiviata(true);
        if (mounted) Navigator.of(context).pop(true);
      case DetailAction.ripristina:
        await controller.setArchiviata(false);
        if (mounted) Navigator.of(context).pop(true);
      case DetailAction.elimina:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminare la trasferta?'),
            content: const Text(
                'Verranno eliminate anche tutte le spese e le foto.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annulla')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Elimina')),
            ],
          ),
        );
        if (confirmed == true) {
          await controller.elimina();
          if (mounted) Navigator.of(context).pop(true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.trasferta;
        return Scaffold(
          appBar: AppBar(
            title: Text(t?.nome ?? ''),
            actions: [
              PopupMenuButton<DetailAction>(
                onSelected: _onAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: DetailAction.modifica, child: Text('Modifica')),
                  if (t?.archiviata ?? false)
                    const PopupMenuItem(
                        value: DetailAction.ripristina,
                        child: Text('Ripristina'))
                  else
                    const PopupMenuItem(
                        value: DetailAction.archivia,
                        child: Text('Archivia')),
                  const PopupMenuItem(
                      value: DetailAction.elimina, child: Text('Elimina')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Inserimento spese: fase 3')),
            ),
            child: const Icon(Symbols.add),
          ),
          body: controller.loading && t == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TotalsHeader(controller: controller),
                    const SizedBox(height: 16),
                    if (controller.speseByData.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Center(
                            child: Text('Nessuna spesa registrata')),
                      )
                    else
                      for (final entry in controller.speseByData.entries) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            formatDate(entry.key),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                        for (final spesa in entry.value) _SpesaTile(spesa),
                      ],
                  ],
                ),
        );
      },
    );
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.controller});

  final TrasfertaDetailController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totale trasferta',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            Text(
              formatEur(controller.totaleEur),
              style: textTheme.headlineMedium?.copyWith(
                fontFeatures: amountFontFeatures,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (controller.countSenzaEur > 0)
              Text(
                '${controller.countSenzaEur} spese senza conversione EUR',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            if (controller.totaliPerValuta.length > 1 ||
                (controller.totaliPerValuta.isNotEmpty &&
                    !controller.totaliPerValuta.containsKey('EUR')))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  controller.totaliPerValuta.entries
                      .map((e) =>
                          '${e.key} ${formatImporto(e.value)}')
                      .join(' · '),
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpesaTile extends StatelessWidget {
  const _SpesaTile(this.spesa);

  final Spesa spesa;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(spesa.categoria.icon, color: AppColors.primary),
        title: Text(spesa.fornitore ?? spesa.categoria.label),
        subtitle: Text(spesa.categoria.label),
        trailing: Text(
          '${spesa.valuta} ${formatImporto(spesa.importo)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFeatures: amountFontFeatures,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test** → PASS.

---

### Task 7: TrasferteListScreen (lista + empty state + FAB)

**Files:**
- Create: `lib/ui/trasferte/trasferte_list_screen.dart`
- Test: `test/trasferte_list_screen_test.dart`

**Interfaces:**
- Consumes: `TrasferteListController`, `TripCard`, `TrasfertaFormScreen`, `TrasfertaDetailScreen`/`TrasfertaDetailController`, repositories (per costruire il detail controller alla navigazione).
- Produces: `class TrasferteListScreen extends StatefulWidget` con ctor `({required TrasferteListController controller, required TrasfertaRepository trasfertaRepository, required SpesaRepository spesaRepository})`. `load()` in initState. Header totale complessivo (solo tab attive: `!controller.archiviate`); empty state "Nessuna trasferta\nCrea la tua prima trasferta" (attive) / "Nessuna trasferta archiviata" (archivio); FAB "+" solo su attive → form crea; tap card → detail (al ritorno `load()`); menu card → archivia/ripristina/elimina (conferma).

- [ ] **Step 1: Write the failing test**

```dart
// test/trasferte_list_screen_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/shared/widgets/trip_card.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;

  setUp(() {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
  });

  tearDown(() => dbHelper.close());

  Future<void> pump(WidgetTester tester, {bool archiviate = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasferteListScreen(
        controller: TrasferteListController(trasfertaRepo, spesaRepo,
            archiviate: archiviate),
        trasfertaRepository: trasfertaRepo,
        spesaRepository: spesaRepo,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Trasferta trasferta({String nome = 'Trip', bool archiviata = false}) =>
      Trasferta(
        nome: nome,
        dataInizio: DateTime(2026, 7, 15),
        archiviata: archiviata,
        createdAt: DateTime(2026, 7, 15, 8),
      );

  testWidgets('shows empty state with CTA on active tab', (tester) async {
    await pump(tester);
    expect(find.text('Nessuna trasferta'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('lists active trips with total header', (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await pump(tester);

    expect(find.byType(TripCard), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Totale complessivo'), findsOneWidget);
  });

  testWidgets('create flow: FAB → form → save → list updated',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo-nome')), 'Milano');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Milano'), findsOneWidget);
    expect(await trasfertaRepo.getAttive(), hasLength(1));
  });

  testWidgets('archive tab: no FAB, no header, shows archived',
      (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    await pump(tester, archiviate: true);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Totale complessivo'), findsNothing);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsOneWidget);
  });

  testWidgets('card menu elimina asks confirmation then deletes',
      (tester) async {
    await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await pump(tester);

    await tester.tap(find.byType(PopupMenuButton<TripCardAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina').last); // confirm dialog
    await tester.pumpAndSettle();

    expect(find.byType(TripCard), findsNothing);
    expect(await trasfertaRepo.getAttive(), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/trasferte/trasferte_list_screen.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../shared/widgets/trip_card.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_detail_screen.dart';
import 'trasferta_form_screen.dart';
import 'trasferte_list_controller.dart';

/// Trip list, used by both the "Trasferte" tab (controller.archiviate ==
/// false: total header + FAB) and the "Archivio" tab (archiviate == true).
class TrasferteListScreen extends StatefulWidget {
  const TrasferteListScreen({
    super.key,
    required this.controller,
    required this.trasfertaRepository,
    required this.spesaRepository,
  });

  final TrasferteListController controller;
  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;

  @override
  State<TrasferteListScreen> createState() => _TrasferteListScreenState();
}

class _TrasferteListScreenState extends State<TrasferteListScreen> {
  TrasferteListController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  Future<void> _openForm() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrasfertaFormScreen(onSave: controller.create),
    ));
    await controller.load();
  }

  Future<void> _openDetail(int trasfertaId) async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => TrasfertaDetailScreen(
        controller: TrasfertaDetailController(trasfertaId,
            widget.trasfertaRepository, widget.spesaRepository),
      ),
    ));
    await controller.load();
  }

  Future<void> _elimina(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la trasferta?'),
        content:
            const Text('Verranno eliminate anche tutte le spese e le foto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed == true) await controller.elimina(id);
  }

  @override
  Widget build(BuildContext context) {
    final archivio = controller.archiviate;
    return Scaffold(
      appBar: AppBar(title: Text(archivio ? 'Archivio' : 'Trasferte')),
      floatingActionButton: archivio
          ? null
          : FloatingActionButton(
              onPressed: _openForm,
              child: const Icon(Symbols.add),
            ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.loading && controller.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.items.isEmpty) {
            return _EmptyState(archivio: archivio, onCreate: _openForm);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!archivio) ...[
                _TotalHeader(totale: controller.totaleComplessivoEur),
                const SizedBox(height: 12),
              ],
              for (final item in controller.items)
                TripCard(
                  item: item,
                  onTap: () => _openDetail(item.trasferta.id!),
                  onArchivia: () =>
                      controller.setArchiviata(item.trasferta.id!, true),
                  onRipristina: () =>
                      controller.setArchiviata(item.trasferta.id!, false),
                  onElimina: () => _elimina(item.trasferta.id!),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.totale});

  final double totale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archivio, required this.onCreate});

  final bool archivio;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.flight_takeoff,
              size: 56, color: AppColors.textTertiaryLight),
          const SizedBox(height: 12),
          Text(
            archivio ? 'Nessuna trasferta archiviata' : 'Nessuna trasferta',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!archivio) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Symbols.add),
              label: const Text('Crea la tua prima trasferta'),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test** → PASS.

---

### Task 8: HomeShell (NavigationBar 3 tab)

**Files:**
- Create: `lib/ui/shell/home_shell.dart`
- Test: `test/home_shell_test.dart`
- Delete: `lib/ui/shell/.gitkeep`

**Interfaces:**
- Consumes: `TrasferteListScreen`, `TrasferteListController`, repositories, `appVersion`.
- Produces: `class HomeShell extends StatefulWidget` con ctor `({required TrasfertaRepository trasfertaRepository, required SpesaRepository spesaRepository})`. Crea due `TrasferteListController` (attive/archivio) e li dispone. `NavigationBar` 3 destinazioni: Trasferte (`Symbols.receipt_long`), Archivio (`Symbols.archive`), Impostazioni (`Symbols.settings`). Body via `IndexedStack`; al cambio tab ricarica il controller della tab selezionata (0/1). Tab Impostazioni = placeholder con `appVersion` (schermata completa in fase 8).

- [ ] **Step 1: Write the failing test**

```dart
// test/home_shell_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/shell/home_shell.dart';
import 'package:nota_spese/version.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;

  setUp(() {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
  });

  tearDown(() => dbHelper.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(
        trasfertaRepository: trasfertaRepo,
        spesaRepository: spesaRepo,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows three destinations and starts on Trasferte',
      (tester) async {
    await pump(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Nessuna trasferta'), findsOneWidget);
  });

  testWidgets('switching to Archivio shows archived list', (tester) async {
    await trasfertaRepo.insert(Trasferta(
      nome: 'Old',
      dataInizio: DateTime(2026, 5, 1),
      archiviata: true,
      createdAt: DateTime(2026, 5, 1),
    ));
    await pump(tester);

    await tester.tap(find.text('Archivio'));
    await tester.pumpAndSettle();

    expect(find.text('Old'), findsOneWidget);
    expect(find.text('ARCHIVIATA'), findsOneWidget);
  });

  testWidgets('Impostazioni tab shows placeholder with version',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(find.textContaining(appVersion), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify FAIL.**

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/shell/home_shell.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../version.dart';
import '../trasferte/trasferte_list_controller.dart';
import '../trasferte/trasferte_list_screen.dart';

/// Root scaffold: NavigationBar with the three tabs from the mockup.
/// Tab switches reload the selected list so cross-tab mutations
/// (archive/restore) stay in sync.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.trasfertaRepository,
    required this.spesaRepository,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final TrasferteListController _attiveController =
      TrasferteListController(
          widget.trasfertaRepository, widget.spesaRepository,
          archiviate: false);
  late final TrasferteListController _archivioController =
      TrasferteListController(
          widget.trasfertaRepository, widget.spesaRepository,
          archiviate: true);

  @override
  void dispose() {
    _attiveController.dispose();
    _archivioController.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    if (index == 0) _attiveController.load();
    if (index == 1) _archivioController.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TrasferteListScreen(
            controller: _attiveController,
            trasfertaRepository: widget.trasfertaRepository,
            spesaRepository: widget.spesaRepository,
          ),
          TrasferteListScreen(
            controller: _archivioController,
            trasfertaRepository: widget.trasfertaRepository,
            spesaRepository: widget.spesaRepository,
          ),
          const _ImpostazioniPlaceholder(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
              icon: Icon(Symbols.receipt_long), label: 'Trasferte'),
          NavigationDestination(
              icon: Icon(Symbols.archive), label: 'Archivio'),
          NavigationDestination(
              icon: Icon(Symbols.settings), label: 'Impostazioni'),
        ],
      ),
    );
  }
}

/// Full settings screen arrives in fase 8.
class _ImpostazioniPlaceholder extends StatelessWidget {
  const _ImpostazioniPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: Center(
        child: Text(
          'Impostazioni — in arrivo (fase 8)\nNota Spese v$appVersion',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Delete `lib/ui/shell/.gitkeep`; run test** → PASS.

---

### Task 9: Composizione app + verifica fase + bump

**Files:**
- Modify: `lib/main.dart` (composizione: DbHelper → repository → app)
- Modify: `lib/app.dart` (rimuovere `_PlaceholderHome`, home = `HomeShell`)
- Modify: `test/widget_test.dart` (smoke test con repository ffi)
- Modify: `pubspec.yaml` (`0.3.0+3`), `lib/version.dart` (`'0.3.0'`)
- Modify: `ToDo.md` (checkbox fase 2)

**Interfaces:**
- Consumes: tutto quanto sopra. `path_provider` per `basePathProvider` prod.

- [ ] **Step 1: Update smoke test (RED prima dell'implementazione)**

```dart
// test/widget_test.dart
// Smoke test: the app builds with the home shell.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/app.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('App builds and shows the shell', (WidgetTester tester) async {
    final dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    final trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    final spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    addTearDown(dbHelper.close);

    await tester.pumpWidget(NotaSpeseApp(
      trasfertaRepository: trasfertaRepo,
      spesaRepository: spesaRepo,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run per RED, poi implementare app/main**

```dart
// lib/app.dart
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';
import 'ui/shell/home_shell.dart';

class NotaSpeseApp extends StatelessWidget {
  const NotaSpeseApp({
    super.key,
    required this.trasfertaRepository,
    required this.spesaRepository,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nota Spese',
      theme: AppTheme.light(),
      home: HomeShell(
        trasfertaRepository: trasfertaRepository,
        spesaRepository: spesaRepository,
      ),
    );
  }
}
```

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db/db_helper.dart';
import 'data/repositories/foto_repository.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Manual composition (no DI package, Specifiche.md §Architettura).
  final dbHelper = DbHelper();
  final fotoRepository = FotoRepository(
    dbHelper,
    // Photo directory becomes configurable in fase 4 (SettingsService).
    basePathProvider: () async =>
        (await getApplicationDocumentsDirectory()).path,
  );
  final trasfertaRepository = TrasfertaRepository(dbHelper, fotoRepository);
  final spesaRepository = SpesaRepository(dbHelper, fotoRepository);

  runApp(NotaSpeseApp(
    trasfertaRepository: trasfertaRepository,
    spesaRepository: spesaRepository,
  ));
}
```

- [ ] **Step 3: Full verify** — `flutter test` (tutto verde) + `flutter analyze` (zero issue).

- [ ] **Step 4: Bump** — `pubspec.yaml` → `0.3.0+3`; `lib/version.dart` → `'0.3.0'`.

- [ ] **Step 5: ToDo.md** — spuntare checkbox fase 2; verifica emulatore = SKIP esplicito con nota gotcha ambiente (compensata da widget test CRUD completo).

- [ ] **Step 6: Re-run `flutter test` + `flutter analyze`** → verdi.

- [ ] **Step 7: STOP — niente commit automatico.** Riferire esito; commit solo su richiesta.
