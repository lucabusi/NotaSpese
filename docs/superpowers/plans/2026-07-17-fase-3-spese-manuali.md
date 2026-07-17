# Fase 3 — Spese (inserimento manuale) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inserimento/modifica/eliminazione manuale delle spese di una trasferta, con tastiera numerica custom, currency picker searchable, chip categoria e dettaglio trasferta completo (barre totali per categoria).

**Architecture:** Nuova cartella `lib/ui/spese/` (form + keypad + logica input importo come `ValueNotifier` testabile) e due widget condivisi in `lib/ui/shared/widgets/` (currency picker, category chips). `TrasfertaDetailController` acquisisce i metodi CRUD spese e `totaliEurPerCategoria`; `TrasfertaDetailScreen` sostituisce il FAB placeholder con il bottom sheet 📷/✏️ e aggiunge le barre. Nessun nuovo package.

**Tech Stack:** Flutter (Material 3), sqflite (via repository esistenti), `material_symbols_icons`, test con `flutter_test` + `sqflite_common_ffi`.

## Global Constraints

- UI in italiano; codice, commit e identificatori in inglese (ToDo.md §Convenzioni).
- Mai `sqflite`/filesystem dai controller: solo repository (ToDo.md §Convenzioni).
- Widget test che toccano il DB: **`databaseFactoryFfiNoIsolate`**, mai `databaseFactoryFfi` (gotcha FakeAsync, memoria progetto). Unit test puri: `databaseFactoryFfi` ok.
- `Spesa.valuta` = stringa ISO grezza; enum `Currency` ha `try_` per TRY → salvare sempre `.code`, mai `.name`.
- Verifica fase: `flutter analyze` zero issue + `flutter test` verde. Prova su emulatore = SKIP esplicito (ambiente Android incompleto, gotcha CLAUDE.md), compensata da widget test del flusso completo.
- Bump versione a fine fase: `pubspec.yaml` `0.4.0+4` + `lib/version.dart` `'0.4.0'`.
- Design tokens esistenti: `AppColors`, `AppRadius`, `amountFontFeatures` da `core/theme/app_theme.dart`. Icone `Symbols.*`.
- Chiavi widget nei form: pattern `Key('campo-...')` / `Key('chip-...')` come in `trasferta_form_screen.dart`.
- Commit alla fine di ogni task (regola utente: commit solo su richiesta esplicita — se l'utente non l'ha data, accumulare e proporre un commit unico a fine fase).

## File Structure

- Create: `lib/ui/spese/amount_input_controller.dart` — stato input importo (cifre/virgola/backspace), `ValueNotifier<String>`
- Create: `lib/ui/spese/amount_keypad.dart` — griglia 3×4 che pilota il controller
- Create: `lib/ui/shared/widgets/currency_picker.dart` — `CurrencyPickerScreen` fullscreen searchable
- Create: `lib/ui/shared/widgets/category_chips.dart` — `CategoryChips` (ChoiceChip icona+label)
- Create: `lib/ui/spese/spesa_form_screen.dart` — form crea/modifica/elimina spesa
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart` — CRUD spese + `totaliEurPerCategoria`
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart` — bottom sheet FAB, tap su spesa → modifica, barre categoria
- Modify: `pubspec.yaml`, `lib/version.dart`, `ToDo.md` (chiusura fase)
- Test: `test/amount_input_controller_test.dart`, `test/amount_keypad_test.dart`, `test/currency_picker_test.dart`, `test/category_chips_test.dart`, `test/spesa_form_screen_test.dart`; Modify: `test/trasferta_detail_controller_test.dart`, `test/trasferta_detail_screen_test.dart`

---

### Task 1: AmountInputController (logica input importo)

**Files:**
- Create: `lib/ui/spese/amount_input_controller.dart`
- Test: `test/amount_input_controller_test.dart`

**Interfaces:**
- Consumes: niente (solo `flutter/foundation`).
- Produces: `class AmountInputController extends ValueNotifier<String>` con costruttore `AmountInputController({int decimalDigits = 2, String initial = ''})`, getter/setter `int decimalDigits`, `void addDigit(int digit)`, `void addDecimalSeparator()`, `void backspace()`, `double? get amount`, `static String initialText(double importo, int decimalDigits)`. Il valore è la stringa digitata con `,` come separatore decimale (es. `'12,5'`), vuota = nessun input.

- [ ] **Step 1: Write the failing test**

```dart
// test/amount_input_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/ui/spese/amount_input_controller.dart';

void main() {
  test('digits append; leading zero is replaced', () {
    final c = AmountInputController();
    c.addDigit(0);
    expect(c.value, '0');
    c.addDigit(5); // '0' + digit → digit
    expect(c.value, '5');
    c.addDigit(2);
    expect(c.value, '52');
  });

  test('decimal separator: empty → "0,"; only once; respects decimalDigits',
      () {
    final c = AmountInputController();
    c.addDecimalSeparator();
    expect(c.value, '0,');
    c.addDecimalSeparator(); // no-op
    expect(c.value, '0,');
    c.addDigit(1);
    c.addDigit(2);
    expect(c.value, '0,12');
    c.addDigit(9); // oltre 2 decimali → ignorato
    expect(c.value, '0,12');
  });

  test('decimalDigits 0 (JPY): separator is a no-op', () {
    final c = AmountInputController(decimalDigits: 0);
    c.addDigit(3);
    c.addDecimalSeparator();
    c.addDigit(5);
    expect(c.value, '35');
  });

  test('backspace removes last char; no-op when empty', () {
    final c = AmountInputController(initial: '12,5');
    c.backspace();
    expect(c.value, '12,');
    c.backspace();
    c.backspace();
    c.backspace();
    expect(c.value, '');
    c.backspace();
    expect(c.value, '');
  });

  test('integer part capped at maxIntegerDigits', () {
    final c = AmountInputController();
    for (var i = 0; i < 12; i++) {
      c.addDigit(9);
    }
    expect(c.value.length, AmountInputController.maxIntegerDigits);
  });

  test('amount parses the comma value; empty → null', () {
    expect(AmountInputController().amount, isNull);
    expect(AmountInputController(initial: '12,5').amount, 12.5);
    expect(AmountInputController(initial: '12,').amount, 12.0);
    expect(AmountInputController(initial: '3000').amount, 3000.0);
  });

  test('lowering decimalDigits truncates existing decimals', () {
    final c = AmountInputController(initial: '12,34');
    c.decimalDigits = 0; // switch a valuta senza decimali
    expect(c.value, '12');
    final d = AmountInputController(initial: '1,234', decimalDigits: 3);
    d.decimalDigits = 2;
    expect(d.value, '1,23');
  });

  test('initialText formats for editing without trailing zeros', () {
    expect(AmountInputController.initialText(12.5, 2), '12,5');
    expect(AmountInputController.initialText(12, 2), '12');
    expect(AmountInputController.initialText(3000, 0), '3000');
    expect(AmountInputController.initialText(9.99, 2), '9,99');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/amount_input_controller_test.dart`
Expected: FAIL (file `amount_input_controller.dart` inesistente / compile error)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/spese/amount_input_controller.dart
import 'package:flutter/foundation.dart';

/// Raw amount typed on the custom keypad. Value is the digit string with
/// ',' as decimal separator (e.g. '12,5'); empty string = no input yet.
/// All input rules live here so the keypad widget stays dumb.
class AmountInputController extends ValueNotifier<String> {
  AmountInputController({int decimalDigits = 2, String initial = ''})
      : _decimalDigits = decimalDigits,
        super(initial);

  static const int maxIntegerDigits = 9;

  int _decimalDigits;
  int get decimalDigits => _decimalDigits;

  /// Currency switch: decimals beyond the new limit are truncated.
  set decimalDigits(int digits) {
    _decimalDigits = digits;
    final i = value.indexOf(',');
    if (i < 0) return;
    if (digits == 0) {
      value = value.substring(0, i);
    } else if (value.length - i - 1 > digits) {
      value = value.substring(0, i + 1 + digits);
    }
  }

  void addDigit(int digit) {
    assert(digit >= 0 && digit <= 9);
    final i = value.indexOf(',');
    if (i < 0) {
      if (value == '0') {
        value = '$digit';
        return;
      }
      if (value.length >= maxIntegerDigits) return;
    } else if (value.length - i - 1 >= _decimalDigits) {
      return;
    }
    value = '$value$digit';
  }

  void addDecimalSeparator() {
    if (_decimalDigits == 0 || value.contains(',')) return;
    value = value.isEmpty ? '0,' : '$value,';
  }

  void backspace() {
    if (value.isEmpty) return;
    value = value.substring(0, value.length - 1);
  }

  /// Parsed amount, null when nothing was typed.
  double? get amount =>
      value.isEmpty ? null : double.tryParse(value.replaceAll(',', '.'));

  /// Edit-mode seed: stored amount → keypad string, trailing zeros dropped.
  static String initialText(double importo, int decimalDigits) {
    var s = importo.toStringAsFixed(decimalDigits);
    if (decimalDigits > 0) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s.replaceAll('.', ',');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/amount_input_controller_test.dart`
Expected: PASS (8 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/spese/amount_input_controller.dart test/amount_input_controller_test.dart
git commit -m "feat: amount input state for custom keypad"
```

---

### Task 2: AmountKeypad (griglia 3×4)

**Files:**
- Create: `lib/ui/spese/amount_keypad.dart`
- Test: `test/amount_keypad_test.dart`

**Interfaces:**
- Consumes: `AmountInputController` (Task 1).
- Produces: `class AmountKeypad extends StatelessWidget`, costruttore `AmountKeypad({super.key, required AmountInputController controller})`. Chiavi tasti: `Key('key-0')`…`Key('key-9')`, `Key('key-comma')`, `Key('key-backspace')`.

- [ ] **Step 1: Write the failing test**

```dart
// test/amount_keypad_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/ui/spese/amount_input_controller.dart';
import 'package:nota_spese/ui/spese/amount_keypad.dart';

void main() {
  testWidgets('digits, comma and backspace drive the controller',
      (tester) async {
    final c = AmountInputController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AmountKeypad(controller: c)),
    ));

    await tester.tap(find.byKey(const Key('key-1')));
    await tester.tap(find.byKey(const Key('key-2')));
    await tester.tap(find.byKey(const Key('key-comma')));
    await tester.tap(find.byKey(const Key('key-5')));
    expect(c.value, '12,5');

    await tester.tap(find.byKey(const Key('key-backspace')));
    expect(c.value, '12,');

    await tester.tap(find.byKey(const Key('key-0')));
    expect(c.value, '12,0');
  });

  testWidgets('renders 12 keys in 4 rows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AmountKeypad(controller: AmountInputController())),
    ));
    for (var d = 0; d <= 9; d++) {
      expect(find.byKey(Key('key-$d')), findsOneWidget);
    }
    expect(find.byKey(const Key('key-comma')), findsOneWidget);
    expect(find.byKey(const Key('key-backspace')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/amount_keypad_test.dart`
Expected: FAIL (file inesistente)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/spese/amount_keypad.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'amount_input_controller.dart';

/// Custom 3x4 numeric keypad (mockup grid): 1-9, comma, 0, backspace.
/// Input rules (decimals, caps) live in [AmountInputController]; invalid
/// taps are silent no-ops, so every key is always enabled.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.controller});

  final AmountInputController controller;

  static const double _keyHeight = 56;

  Widget _key({required Key key, required Widget child,
      required VoidCallback onTap}) {
    return Expanded(
      child: SizedBox(
        height: _keyHeight,
        child: TextButton(key: key, onPressed: onTap, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    Widget digit(int d) => _key(
          key: Key('key-$d'),
          child: Text('$d', style: style),
          onTap: () => controller.addDigit(d),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [digit(1), digit(2), digit(3)]),
        Row(children: [digit(4), digit(5), digit(6)]),
        Row(children: [digit(7), digit(8), digit(9)]),
        Row(children: [
          _key(
            key: const Key('key-comma'),
            child: Text(',', style: style),
            onTap: controller.addDecimalSeparator,
          ),
          digit(0),
          _key(
            key: const Key('key-backspace'),
            child: const Icon(Symbols.backspace),
            onTap: controller.backspace,
          ),
        ]),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/amount_keypad_test.dart`
Expected: PASS (2 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/spese/amount_keypad.dart test/amount_keypad_test.dart
git commit -m "feat: 3x4 amount keypad widget"
```

---

### Task 3: CurrencyPickerScreen (searchable)

**Files:**
- Create: `lib/ui/shared/widgets/currency_picker.dart`
- Test: `test/currency_picker_test.dart`

**Interfaces:**
- Consumes: `Currency` (`core/constants/currencies.dart`: `.code`, `.nome`, `.symbol`, `.frequente`, `Currency.frequenti`), `AppColors`.
- Produces: `class CurrencyPickerScreen extends StatefulWidget` con `static Future<Currency?> show(BuildContext context, {String? selectedCode})` (push fullscreenDialog, pop con la `Currency` scelta o null). Tile con chiave `Key('valuta-<CODE>')`, campo filtro `Key('filtro-valuta')`.

- [ ] **Step 1: Write the failing test**

```dart
// test/currency_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/currencies.dart';
import 'package:nota_spese/ui/shared/widgets/currency_picker.dart';

void main() {
  Currency? result;

  Future<void> open(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result =
                await CurrencyPickerScreen.show(context, selectedCode: 'EUR');
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets('frequent currencies on top, EUR first', (tester) async {
    await open(tester);

    expect(find.text('FREQUENTI'), findsOneWidget);
    final tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList();
    // Ordine spec §8: EUR, USD, JPY, GBP, CHF, RSD, AED, SGD.
    expect((tiles.first.title! as Text).data, startsWith('EUR'));
    expect(find.byKey(const Key('valuta-JPY')), findsOneWidget);
  });

  testWidgets('text filter narrows the list', (tester) async {
    await open(tester);

    await tester.enterText(find.byKey(const Key('filtro-valuta')), 'yen');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('valuta-JPY')), findsOneWidget);
    expect(find.byKey(const Key('valuta-EUR')), findsNothing);
  });

  testWidgets('tapping a tile pops with that currency', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('valuta-JPY')));
    await tester.pumpAndSettle();

    expect(result, Currency.jpy);
    expect(find.text('apri'), findsOneWidget); // tornati indietro
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/currency_picker_test.dart`
Expected: FAIL (file inesistente)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/shared/widgets/currency_picker.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/theme/app_theme.dart';

/// Fullscreen searchable currency picker (Specifiche.md §8): filter field,
/// frequent currencies on top. Pops the chosen [Currency], null on back.
class CurrencyPickerScreen extends StatefulWidget {
  const CurrencyPickerScreen({super.key, this.selectedCode});

  final String? selectedCode;

  static Future<Currency?> show(BuildContext context, {String? selectedCode}) =>
      Navigator.of(context).push<Currency>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CurrencyPickerScreen(selectedCode: selectedCode),
      ));

  @override
  State<CurrencyPickerScreen> createState() => _CurrencyPickerScreenState();
}

class _CurrencyPickerScreenState extends State<CurrencyPickerScreen> {
  String _query = '';

  Widget _tile(Currency c) => ListTile(
        key: Key('valuta-${c.code}'),
        leading: SizedBox(
          width: 44,
          child: Text(
            c.symbol,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        title: Text('${c.code} — ${c.nome}'),
        trailing: c.code == widget.selectedCode
            ? const Icon(Symbols.check, color: AppColors.primary)
            : null,
        onTap: () => Navigator.of(context).pop(c),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtrate = q.isEmpty
        ? const <Currency>[]
        : Currency.values
            .where((c) =>
                c.code.toLowerCase().contains(q) ||
                c.nome.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Valuta')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('filtro-valuta'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.search),
                hintText: 'Cerca per codice o nome',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: q.isNotEmpty
                ? ListView(children: [for (final c in filtrate) _tile(c)])
                : ListView(
                    children: [
                      const _SectionHeader('Frequenti'),
                      for (final c in Currency.frequenti) _tile(c),
                      const Divider(),
                      const _SectionHeader('Tutte le valute'),
                      for (final c
                          in Currency.values.where((c) => !c.frequente))
                        _tile(c),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textTertiary, letterSpacing: 1),
          ),
        ),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/currency_picker_test.dart`
Expected: PASS (3 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/shared/widgets/currency_picker.dart test/currency_picker_test.dart
git commit -m "feat: searchable currency picker screen"
```

---

### Task 4: CategoryChips

**Files:**
- Create: `lib/ui/shared/widgets/category_chips.dart`
- Test: `test/category_chips_test.dart`

**Interfaces:**
- Consumes: `Categoria` (`core/constants/categories.dart`: `.label`, `.icon`).
- Produces: `class CategoryChips extends StatelessWidget`, costruttore `CategoryChips({super.key, required Categoria selected, required ValueChanged<Categoria> onSelected})`. Chip con chiave `Key('chip-<name>')` (es. `chip-cena`).

- [ ] **Step 1: Write the failing test**

```dart
// test/category_chips_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/ui/shared/widgets/category_chips.dart';

void main() {
  testWidgets('renders one chip per category and reports taps',
      (tester) async {
    Categoria? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CategoryChips(
            selected: Categoria.pranzo,
            onSelected: (c) => tapped = c,
          ),
        ),
      ),
    ));

    expect(find.byType(ChoiceChip), findsNWidgets(Categoria.values.length));

    final pranzo =
        tester.widget<ChoiceChip>(find.byKey(const Key('chip-pranzo')));
    expect(pranzo.selected, isTrue);

    await tester.tap(find.byKey(const Key('chip-cena')));
    expect(tapped, Categoria.cena);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/category_chips_test.dart`
Expected: FAIL (file inesistente)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/shared/widgets/category_chips.dart
import 'package:flutter/material.dart';

import '../../../core/constants/categories.dart';

/// Single-select category chips (icon + label), one per [Categoria].
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Categoria selected;
  final ValueChanged<Categoria> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in Categoria.values)
          ChoiceChip(
            key: Key('chip-${c.name}'),
            avatar: Icon(c.icon, size: 18),
            label: Text(c.label),
            selected: c == selected,
            onSelected: (_) => onSelected(c),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/category_chips_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/shared/widgets/category_chips.dart test/category_chips_test.dart
git commit -m "feat: category choice chips widget"
```

---

### Task 5: TrasfertaDetailController — CRUD spese + totali per categoria

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart`
- Test: `test/trasferta_detail_controller_test.dart` (aggiunta test + un expect)

**Interfaces:**
- Consumes: `SpesaRepository.insert/update/delete/totaliEurPerCategoria` (già esistenti).
- Produces: sul controller: campo `Map<Categoria, double> totaliEurPerCategoria` (popolato in `load()`), `Future<void> createSpesa(Spesa spesa)`, `Future<void> updateSpesa(Spesa spesa)`, `Future<void> deleteSpesa(int id)` — tutti ricaricano lo stato con `load()`.

- [ ] **Step 1: Write the failing test**

In `test/trasferta_detail_controller_test.dart`, nel test esistente `'load exposes trip, grouped spese and totals'` aggiungere in fondo (dopo `expect(c.totaliPerValuta, ...)`):

```dart
    expect(c.totaliEurPerCategoria, {Categoria.taxi: 20.0});
```

e aggiungere questo nuovo test prima della chiusura di `main()`:

```dart
  test('spese CRUD reloads grouped list and totals', () async {
    final c = controller();
    await c.load();

    await c.createSpesa(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 40,
      valuta: 'EUR',
      importoEur: 40,
      createdAt: DateTime(2026, 7, 11, 21),
    ));
    expect(c.speseByData, hasLength(1));
    expect(c.totaleEur, 40);
    expect(c.totaliEurPerCategoria, {Categoria.cena: 40.0});

    final salvata = c.speseByData.values.first.first;
    await c.updateSpesa(Spesa(
      id: salvata.id,
      trasfertaId: trasfertaId,
      data: salvata.data,
      categoria: Categoria.pranzo,
      importo: 25,
      valuta: 'EUR',
      importoEur: 25,
      createdAt: salvata.createdAt,
    ));
    expect(c.totaleEur, 25);
    expect(c.totaliEurPerCategoria, {Categoria.pranzo: 25.0});

    await c.deleteSpesa(salvata.id!);
    expect(c.speseByData, isEmpty);
    expect(c.totaleEur, 0);
    expect(c.totaliEurPerCategoria, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/trasferta_detail_controller_test.dart`
Expected: FAIL ("The getter 'totaliEurPerCategoria' isn't defined" / metodi mancanti)

- [ ] **Step 3: Write minimal implementation**

In `lib/ui/trasferte/trasferta_detail_controller.dart`:

1. Aggiungere import in testa (dopo `import 'package:flutter/foundation.dart';`):

```dart
import '../../core/constants/categories.dart';
```

2. Dopo il campo `Map<String, double> totaliPerValuta = {};` aggiungere:

```dart
  Map<Categoria, double> totaliEurPerCategoria = {};
```

3. In `load()`, dopo la riga `totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);` aggiungere:

```dart
    totaliEurPerCategoria =
        await _spesaRepository.totaliEurPerCategoria(trasfertaId);
```

4. Dopo `setArchiviata` (prima di `elimina`) aggiungere:

```dart
  Future<void> createSpesa(Spesa spesa) async {
    await _spesaRepository.insert(spesa);
    await load();
  }

  Future<void> updateSpesa(Spesa spesa) async {
    await _spesaRepository.update(spesa);
    await load();
  }

  Future<void> deleteSpesa(int id) async {
    await _spesaRepository.delete(id);
    await load();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/trasferta_detail_controller_test.dart`
Expected: PASS (3 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/trasferte/trasferta_detail_controller.dart test/trasferta_detail_controller_test.dart
git commit -m "feat: spese crud + category totals in detail controller"
```

---

### Task 6: SpesaFormScreen (form manuale)

**Files:**
- Create: `lib/ui/spese/spesa_form_screen.dart`
- Test: `test/spesa_form_screen_test.dart`

**Interfaces:**
- Consumes: `AmountInputController`, `AmountKeypad`, `CurrencyPickerScreen.show`, `CategoryChips`, `Spesa`, `Currency.fromCode`, `formatDate`, `AppColors`/`amountFontFeatures`.
- Produces: `class SpesaFormScreen extends StatefulWidget`, costruttore `SpesaFormScreen({super.key, required int trasfertaId, required String valutaDefault, Spesa? initial, required Future<void> Function(Spesa spesa) onSave, Future<void> Function()? onDelete})`. `initial == null` → crea (data default oggi, valuta = `valutaDefault`); altrimenti modifica (id/createdAt/ocrEngine/tassoCambio preservati). `onDelete != null` → bottone "Elimina spesa" con dialog di conferma; dopo conferma chiama `onDelete` e fa pop. Regola EUR: campo "Importo EUR" vuoto + valuta `EUR` → `importoEur = importo` (una spesa in euro è già convertita); vuoto + altra valuta → `importoEur = null` (conversione automatica in fase 6). Chiavi: `campo-valuta`, `campo-importo-eur`, `campo-data`, `campo-fornitore`, `campo-note`, `salva-spesa`, `elimina-spesa`, `display-importo`.

- [ ] **Step 1: Write the failing test**

```dart
// test/spesa_form_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/ui/spese/spesa_form_screen.dart';

void main() {
  Spesa? saved;
  var deleted = false;

  Future<void> pumpForm(WidgetTester tester,
      {Spesa? initial, bool withDelete = false}) async {
    saved = null;
    deleted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SpesaFormScreen(
              trasfertaId: 1,
              valutaDefault: 'EUR',
              initial: initial,
              onSave: (s) async => saved = s,
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

  testWidgets('saves manual expense; EUR currency auto-fills importo_eur',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('key-1')));
    await tester.tap(find.byKey(const Key('key-2')));
    await tester.tap(find.byKey(const Key('key-comma')));
    await tester.tap(find.byKey(const Key('key-5')));
    await tester.pump();
    expect(find.text('12,5'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('chip-cena')));
    await tester.tap(find.byKey(const Key('chip-cena')));
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    expect(saved!.importo, 12.5);
    expect(saved!.valuta, 'EUR');
    expect(saved!.importoEur, 12.5);
    expect(saved!.categoria, Categoria.cena);
    expect(saved!.trasfertaId, 1);
    expect(saved!.ocrEngine, isNull);
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

    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    expect(saved!.valuta, 'JPY');
    expect(saved!.importo, 35);
    expect(saved!.importoEur, isNull);
  });

  testWidgets('empty amount blocks save with a snackbar', (tester) async {
    await pumpForm(tester);

    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
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
    expect(find.text('Taxi Roma'), findsOneWidget);

    // Salva preserva id e createdAt.
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(saved!.id, 7);
    expect(saved!.createdAt, DateTime(2026, 7, 11, 9));

    // Riapre per il percorso elimina.
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('elimina-spesa')));
    await tester.tap(find.byKey(const Key('elimina-spesa')));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare la spesa?'), findsOneWidget);

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('apri'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/spesa_form_screen_test.dart`
Expected: FAIL (file inesistente)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/spese/spesa_form_screen.dart
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/currencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/spesa.dart';
import '../shared/widgets/category_chips.dart';
import '../shared/widgets/currency_picker.dart';
import 'amount_input_controller.dart';
import 'amount_keypad.dart';

/// Create/edit expense form. [initial] == null → create; otherwise edit
/// (id, createdAt, ocrEngine and tassoCambio are preserved). The amount is
/// typed only on the custom keypad, so the system keyboard never covers it
/// (spec UX). [onDelete] non-null → "Elimina spesa" with confirmation.
class SpesaFormScreen extends StatefulWidget {
  const SpesaFormScreen({
    super.key,
    required this.trasfertaId,
    required this.valutaDefault,
    this.initial,
    required this.onSave,
    this.onDelete,
  });

  final int trasfertaId;
  final String valutaDefault;
  final Spesa? initial;
  final Future<void> Function(Spesa spesa) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<SpesaFormScreen> createState() => _SpesaFormScreenState();
}

class _SpesaFormScreenState extends State<SpesaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _valuta = widget.initial?.valuta ?? widget.valutaDefault;
  late final AmountInputController _importo = AmountInputController(
    decimalDigits: _decimalDigits(_valuta),
    initial: widget.initial == null
        ? ''
        : AmountInputController.initialText(
            widget.initial!.importo, _decimalDigits(_valuta)),
  );
  late final TextEditingController _importoEur = TextEditingController(
      text: widget.initial?.importoEur
              ?.toStringAsFixed(2)
              .replaceAll('.', ',') ??
          '');
  late Categoria _categoria = widget.initial?.categoria ?? Categoria.pranzo;
  late DateTime _data = widget.initial?.data ?? DateTime.now();
  late final TextEditingController _fornitore =
      TextEditingController(text: widget.initial?.fornitore ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');

  static int _decimalDigits(String code) =>
      Currency.fromCode(code)?.decimalDigits ?? 2;

  @override
  void dispose() {
    _importo.dispose();
    _importoEur.dispose();
    _fornitore.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickValuta() async {
    final picked =
        await CurrencyPickerScreen.show(context, selectedCode: _valuta);
    if (picked == null) return;
    setState(() {
      _valuta = picked.code;
      _importo.decimalDigits = picked.decimalDigits;
    });
  }

  Future<void> _pickData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _data = picked);
  }

  Future<void> _salva() async {
    final importo = _importo.amount;
    if (importo == null || importo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Inserisci un importo maggiore di zero')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final eurText = _importoEur.text.trim();
    var importoEur =
        eurText.isEmpty ? null : double.parse(eurText.replaceAll(',', '.'));
    // Spesa già in euro: l'importo convertito è l'importo stesso.
    importoEur ??= _valuta == 'EUR' ? importo : null;

    final initial = widget.initial;
    final spesa = Spesa(
      id: initial?.id,
      trasfertaId: widget.trasfertaId,
      data: _data,
      categoria: _categoria,
      fornitore:
          _fornitore.text.trim().isEmpty ? null : _fornitore.text.trim(),
      importo: importo,
      valuta: _valuta,
      importoEur: importoEur,
      tassoCambio: initial?.tassoCambio,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ocrEngine: initial?.ocrEngine,
      createdAt: initial?.createdAt ?? DateTime.now(),
    );
    await widget.onSave(spesa);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _elimina() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la spesa?'),
        content: const Text('Verrà eliminata anche la foto, se presente.'),
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
    if (confirmed != true) return;
    await widget.onDelete!();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar:
          AppBar(title: Text(editing ? 'Modifica spesa' : 'Nuova spesa')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListenableBuilder(
              listenable: _importo,
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: Text(
                      _importo.value.isEmpty ? '0' : _importo.value,
                      key: const Key('display-importo'),
                      style: textTheme.displaySmall?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('campo-valuta'),
                    onPressed: _pickValuta,
                    icon: const Icon(Symbols.expand_more),
                    label: Text(
                      _valuta,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            AmountKeypad(controller: _importo),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-importo-eur'),
              controller: _importoEur,
              decoration: const InputDecoration(
                  labelText: 'Importo EUR (opzionale)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                return double.tryParse(t.replaceAll(',', '.')) == null
                    ? 'Importo non valido'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            CategoryChips(
              selected: _categoria,
              onSelected: (c) => setState(() => _categoria = c),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('campo-data'),
              onPressed: _pickData,
              child: Text('Data: ${formatDate(_data)}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-fornitore'),
              controller: _fornitore,
              decoration: const InputDecoration(labelText: 'Fornitore'),
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
              key: const Key('salva-spesa'),
              onPressed: _salva,
              child: const Text('Salva'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('elimina-spesa'),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _elimina,
                child: const Text('Elimina spesa'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/spesa_form_screen_test.dart`
Expected: PASS (4 test)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/spese/spesa_form_screen.dart test/spesa_form_screen_test.dart
git commit -m "feat: manual expense form screen"
```

---

### Task 7: Integrazione dettaglio trasferta (bottom sheet, modifica, barre)

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart`
- Test: `test/trasferta_detail_screen_test.dart` (sostituire il test FAB placeholder, aggiungere flusso completo e barre)

**Interfaces:**
- Consumes: `SpesaFormScreen` (Task 6), `controller.createSpesa/updateSpesa/deleteSpesa/totaliEurPerCategoria` (Task 5), `formatEur`.
- Produces: bottom sheet con `Key('sheet-scatta')` (disabilitato) e `Key('sheet-manuale')`; tap su una spesa apre il form in modifica; card "Totali per categoria (EUR)" con una riga/barra per categoria.

- [ ] **Step 1: Write the failing tests**

In `test/trasferta_detail_screen_test.dart` **sostituire** il test `'FAB shows fase-3 placeholder snackbar'` con:

```dart
  testWidgets('FAB opens add sheet: camera disabled, manual opens form',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final scatta =
        tester.widget<ListTile>(find.byKey(const Key('sheet-scatta')));
    expect(scatta.enabled, isFalse);

    await tester.tap(find.byKey(const Key('sheet-manuale')));
    await tester.pumpAndSettle();
    expect(find.text('Nuova spesa'), findsOneWidget);
  });

  testWidgets('manual expense flow: create, totals, edit, delete',
      (tester) async {
    await pump(tester);

    // Crea: 12 EUR, categoria Cena.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-manuale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('key-1')));
    await tester.tap(find.byKey(const Key('key-2')));
    await tester.ensureVisible(find.byKey(const Key('chip-cena')));
    await tester.tap(find.byKey(const Key('chip-cena')));
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();

    // Lista + totali aggiornati (header, tile, barra categoria).
    expect(find.text('€ 12,00'), findsWidgets);
    expect(find.text('Totali per categoria (EUR)'), findsOneWidget);
    expect(find.text('Cena'), findsWidgets);

    // Modifica: 12 → 125.
    await tester.tap(find.widgetWithText(ListTile, 'Cena').first);
    await tester.pumpAndSettle();
    expect(find.text('Modifica spesa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-5')));
    await tester.ensureVisible(find.byKey(const Key('salva-spesa')));
    await tester.tap(find.byKey(const Key('salva-spesa')));
    await tester.pumpAndSettle();
    expect(find.text('€ 125,00'), findsWidgets);

    // Elimina con conferma.
    await tester.tap(find.widgetWithText(ListTile, 'Cena').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('elimina-spesa')));
    await tester.tap(find.byKey(const Key('elimina-spesa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna spesa registrata'), findsOneWidget);
    expect(find.text('Totali per categoria (EUR)'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/trasferta_detail_screen_test.dart`
Expected: FAIL (chiavi `sheet-*` inesistenti, snackbar placeholder ancora presente)

- [ ] **Step 3: Implement the integration**

In `lib/ui/trasferte/trasferta_detail_screen.dart`:

1. Aggiungere import (blocco relativo, in ordine):

```dart
import '../spese/spesa_form_screen.dart';
```

2. Nella classe `_TrasfertaDetailScreenState` aggiungere i metodi (dopo `_onAction`):

```dart
  Future<void> _openAddSheet() async {
    final scelta = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              key: Key('sheet-scatta'),
              leading: Icon(Symbols.photo_camera),
              title: Text('Scatta scontrino'),
              subtitle: Text("Disponibile con l'OCR (fase 4-5)"),
              enabled: false,
            ),
            ListTile(
              key: const Key('sheet-manuale'),
              leading: const Icon(Symbols.edit),
              title: const Text('Inserimento manuale'),
              onTap: () => Navigator.of(context).pop('manuale'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (scelta == 'manuale' && mounted) await _openSpesaForm();
  }

  Future<void> _openSpesaForm({Spesa? spesa}) async {
    final t = controller.trasferta;
    if (t == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SpesaFormScreen(
        trasfertaId: controller.trasfertaId,
        valutaDefault: t.valutaDefault,
        initial: spesa,
        onSave: spesa == null ? controller.createSpesa : controller.updateSpesa,
        onDelete:
            spesa == null ? null : () => controller.deleteSpesa(spesa.id!),
      ),
    ));
  }
```

3. Sostituire il FAB placeholder:

```dart
          floatingActionButton: FloatingActionButton(
            onPressed: _openAddSheet,
            child: const Icon(Symbols.add),
          ),
```

4. Nel body, dopo `_TotalsHeader(controller: controller),` aggiungere:

```dart
                    if (controller.totaliEurPerCategoria.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CategoryTotals(
                          totali: controller.totaliEurPerCategoria),
                    ],
```

5. Passare il tap alla tile: la riga `for (final spesa in entry.value) _SpesaTile(spesa),` diventa:

```dart
                        for (final spesa in entry.value)
                          _SpesaTile(spesa,
                              onTap: () => _openSpesaForm(spesa: spesa)),
```

6. Aggiornare `_SpesaTile`:

```dart
class _SpesaTile extends StatelessWidget {
  const _SpesaTile(this.spesa, {required this.onTap});

  final Spesa spesa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
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

7. Aggiungere in fondo al file (serve anche l'import di `Categoria` e `formatEur`, già coperti da `categories.dart` — da aggiungere — e `formatters.dart` — già presente):

```dart
import '../../core/constants/categories.dart'; // in testa, blocco relativo
```

```dart
/// Per-category EUR totals with proportional bars (mockup "barre").
class _CategoryTotals extends StatelessWidget {
  const _CategoryTotals({required this.totali});

  final Map<Categoria, double> totali;

  @override
  Widget build(BuildContext context) {
    final entries = totali.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totali per categoria (EUR)',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(e.key.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: Text(e.key.label, style: textTheme.bodySmall),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : e.value / max,
                          minHeight: 6,
                          backgroundColor: AppColors.primaryContainer,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatEur(e.value),
                      style: textTheme.bodySmall?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trasferta_detail_screen_test.dart`
Expected: PASS (5 test: 3 esistenti + 2 nuovi)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/trasferte/trasferta_detail_screen.dart test/trasferta_detail_screen_test.dart
git commit -m "feat: expense entry sheet, edit flow and category bars in trip detail"
```

---

### Task 8: Chiusura fase — versione, ToDo, verifica completa

**Files:**
- Modify: `pubspec.yaml` (riga `version:`)
- Modify: `lib/version.dart`
- Modify: `ToDo.md` (sezione Fase 3)

**Interfaces:**
- Consumes: tutto quanto sopra.
- Produces: fase 3 chiusa e verificata.

- [ ] **Step 1: Bump versione**

In `pubspec.yaml`: `version: 0.4.0+4`
In `lib/version.dart`: `const String appVersion = '0.4.0';`

- [ ] **Step 2: Verifica completa**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: tutti i test verdi (69 esistenti + ~18 nuovi)

- [ ] **Step 3: Aggiornare ToDo.md**

Spuntare tutte le checkbox della Fase 3; nella verifica fase, marcare la voce emulatore come SKIP esplicito:

```markdown
## Fase 3 — Spese (inserimento manuale) ✅ 2026-07-17
- [x] Bottom sheet FAB `+`: "📷 Scatta scontrino" (disabilitato fino a fase 4/5) / "✏️ Inserimento manuale"
- [x] Form spesa: importo originale + valuta, importo EUR opzionale, categoria chip-select, data (default oggi, date picker), fornitore, note
- [x] Tastiera numerica custom (griglia 3×4) per importi
- [x] `currency_picker.dart` searchable: filtro testo, valute frequenti in cima (EUR, USD, JPY, GBP, CHF, RSD, AED, SGD)
- [x] Salvataggio/modifica/eliminazione spesa (con conferma)
- [x] Dettaglio trasferta completo: spese raggruppate per data, totali per categoria con barre, totale live
- [x] Unit test: calcolo totali per categoria e formattazione importi

**Verifica fase 3**
- [ ] Flusso completo su emulatore: nuova spesa manuale → appare in lista → totali aggiornati → modifica → elimina — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensato da widget test end-to-end del flusso (crea/modifica/elimina, 2026-07-17)
- [x] `flutter test` + `flutter analyze` verdi (2026-07-17)
```

- [ ] **Step 4: Commit finale**

```bash
git add pubspec.yaml lib/version.dart ToDo.md
git commit -m "chore: bump to 0.4.0, close fase 3 in ToDo"
```

---

## Note di design (decise in pianificazione, 2026-07-17)

- **Regola EUR nel form:** valuta EUR → campo "Importo EUR" **nascosto** e `importo_eur = importo` sempre (in esecuzione è emerso che il campo precompilato restava stantio modificando l'importo di una spesa EUR). Altre valute con campo vuoto → `NULL` (conversione automatica in fase 6).
- **Eliminazione spesa:** dal form di modifica (tap sulla spesa → "Elimina spesa" + conferma), non da swipe sulla lista — un solo percorso, coerente con la conferma esplicita richiesta dalle specifiche.
- **Tastiera:** nessun `TextField` per l'importo (il display è un `Text`), così la tastiera di sistema non si apre mai sopra il keypad custom; le regole di input vivono nel controller testabile, il widget è muto.
- **`tassoCambio`/`ocrEngine`:** preservati in modifica, mai valorizzati dal form manuale (arrivano da fase 5/6).
