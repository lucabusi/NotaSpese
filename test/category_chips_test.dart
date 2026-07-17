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
