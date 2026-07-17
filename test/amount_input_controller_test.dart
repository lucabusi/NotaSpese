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
