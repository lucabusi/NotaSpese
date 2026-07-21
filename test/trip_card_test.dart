import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/ui/shared/widgets/trip_card.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';

void main() {
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

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('shows trip data', (tester) async {
    await pump(tester, TripCard(item: item()));

    expect(find.text('Tokyo Q3'), findsOneWidget);
    expect(find.textContaining('Tokyo ·'), findsOneWidget);
    expect(find.text('JPY'), findsOneWidget);
    expect(find.text('12 spese'), findsOneWidget);
    expect(find.text('¥ 45.320'), findsOneWidget);
    expect(find.text('≈ € 345,50'), findsOneWidget);
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
    await pump(
        tester, TripCard(item: item(), onArchivia: () => archived = true));

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
}
