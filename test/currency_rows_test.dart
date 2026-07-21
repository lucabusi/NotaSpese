import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/ui/shared/currency_rows.dart';

/// [mostraSuggerimentoEur] is the shared rule behind the "≈ € x" hint on
/// both the trip card and the detail header: show it only when something
/// is actually converted, and only when EUR isn't already the (only)
/// currency shown as the primary total.
void main() {
  test('hidden when nothing is converted (totaleEur == 0)', () {
    expect(mostraSuggerimentoEur(0, const {'JPY': 45320.0}), isFalse);
  });

  test('shown when converted and the trip mixes currencies', () {
    expect(mostraSuggerimentoEur(345.5, const {'JPY': 45320.0}), isTrue);
  });

  test('hidden when EUR is already the only currency shown', () {
    expect(mostraSuggerimentoEur(40, const {'EUR': 40.0}), isFalse);
  });

  test('shown when EUR total exists but the trip also has other '
      'currencies', () {
    expect(
        mostraSuggerimentoEur(60, const {'EUR': 40.0, 'USD': 20.0}), isTrue);
  });

  test('empty totals + zero total stays hidden (no spese yet)', () {
    expect(mostraSuggerimentoEur(0, const {}), isFalse);
  });
}
