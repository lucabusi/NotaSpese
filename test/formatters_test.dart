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
