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

    await tester.enterText(find.byKey(const Key('campo-nome')), 'Tokyo Q3');
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

    await tester.enterText(find.byKey(const Key('campo-nome')), 'New name');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved!.id, 7);
    expect(saved!.nome, 'New name');
    expect(saved!.valutaDefault, 'JPY');
    expect(saved!.createdAt, initial.createdAt);
  });

  testWidgets('lingua dropdown offers polish', (tester) async {
    await pump(tester, onSave: (t) async {});

    await tester.tap(find.byKey(const Key('campo-lingua')));
    await tester.pumpAndSettle();

    expect(find.text('Polacco'), findsWidgets);
  });

  testWidgets('saves the selected lingua default', (tester) async {
    Trasferta? saved;
    await pump(tester, onSave: (t) async => saved = t);

    await tester.enterText(find.byKey(const Key('campo-nome')), 'Kraków Q3');
    await tester.tap(find.byKey(const Key('campo-lingua')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polacco').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved!.linguaDefault, 'pl');
  });
}
