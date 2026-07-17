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
