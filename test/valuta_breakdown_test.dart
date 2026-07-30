import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/models/valuta_breakdown.dart';

void main() {
  ValutaBreakdown row(String valuta, double totale) => ValutaBreakdown(
        valuta: valuta,
        count: 1,
        totale: totale,
        totaleEur: 0,
        countSenzaEur: 0,
      );

  test('trip currency comes first, others descending by amount', () {
    final righe = [row('AED', 50), row('JPY', 1000), row('USD', 300)];
    final ordered = ordinaPerValuta(righe, 'AED');
    expect(ordered.map((r) => r.valuta).toList(), ['AED', 'JPY', 'USD']);
  });

  test('without the trip currency, ordering is purely descending', () {
    final righe = [row('USD', 300), row('JPY', 1000)];
    final ordered = ordinaPerValuta(righe, 'EUR');
    expect(ordered.map((r) => r.valuta).toList(), ['JPY', 'USD']);
  });

  test('the input list is not mutated', () {
    final righe = [row('USD', 300), row('JPY', 1000)];
    ordinaPerValuta(righe, 'JPY');
    expect(righe.map((r) => r.valuta).toList(), ['USD', 'JPY']);
  });

  test('empty input yields an empty list', () {
    expect(ordinaPerValuta([], 'EUR'), isEmpty);
  });
}
