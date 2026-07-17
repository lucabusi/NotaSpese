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
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
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
