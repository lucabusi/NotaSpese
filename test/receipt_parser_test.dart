import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/language_profiles.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';

void main() {
  group('parseAmountToken', () {
    test('commaDecimal: 1.234,56 -> 1234.56', () {
      expect(
        parseAmountToken('1.234,56', AmountNumberFormat.commaDecimal),
        1234.56,
      );
    });

    test('commaDecimal with attached currency: €12,50 -> 12.50', () {
      expect(
        parseAmountToken('€12,50', AmountNumberFormat.commaDecimal),
        12.50,
      );
    });

    test('dotDecimal: 1,234.56 -> 1234.56', () {
      expect(
        parseAmountToken('1,234.56', AmountNumberFormat.dotDecimal),
        1234.56,
      );
    });

    test('integerOnly with attached currency: ¥1,200 -> 1200.0', () {
      expect(
        parseAmountToken('¥1,200', AmountNumberFormat.integerOnly),
        1200.0,
      );
    });

    test('integerOnly plain: 1,234 -> 1234.0', () {
      expect(
        parseAmountToken('1,234', AmountNumberFormat.integerOnly),
        1234.0,
      );
    });

    test('non-numeric token -> null', () {
      expect(parseAmountToken('abc', AmountNumberFormat.dotDecimal), null);
    });

    test('separators-only token -> null', () {
      expect(parseAmountToken('.,', AmountNumberFormat.commaDecimal), null);
    });
  });

  group('extractAmount - total keyword per language', () {
    test('IT: totale keyword on same line, rightmost number wins', () {
      final text = 'Articolo 5 - Totale dovuto € 45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });

    test('EN: total keyword picks value', () {
      final text = 'Item 1 5.00\nTotal 25.00';
      expect(extractAmount(text, languageProfiles['en']!), 25.0);
    });

    test('JA: 合計 keyword picks value', () {
      final text = '小計 900円\n合計 1,000円';
      expect(extractAmount(text, languageProfiles['ja']!), 1000.0);
    });

    test('SR: ukupno keyword picks value', () {
      final text = 'Međuzbir 500,00\nUkupno 650,00';
      expect(extractAmount(text, languageProfiles['sr']!), 650.0);
    });

    test('DE: gesamtbetrag keyword picks value', () {
      final text = 'Zwischensumme 10,00\nGesamtbetrag 55,00';
      expect(extractAmount(text, languageProfiles['de']!), 55.0);
    });
  });

  group('extractAmount - negative keyword lines excluded', () {
    test('IT: "Subtotale" line excluded even though it contains "totale"', () {
      final text = 'Subtotale 30,00\nTotale 45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });

    test('EN: "Subtotal" line excluded even though it contains "total"', () {
      final text = 'Subtotal 20.00\nTotal 25.00';
      expect(extractAmount(text, languageProfiles['en']!), 25.0);
    });
  });

  group('extractAmount - OCR column layout', () {
    test('IT: keyword line has no number, value on following line', () {
      final text = 'Totale\n45,00';
      expect(extractAmount(text, languageProfiles['it']!), 45.0);
    });
  });

  group('extractAmount - keyword priority and repeated keyword', () {
    test('EN: earlier-priority keyword wins over later keyword with bigger value', () {
      final text = 'Total 10.00\nAmount Due 999.00';
      expect(extractAmount(text, languageProfiles['en']!), 10.0);
    });

    test('EN: same keyword repeated, max value wins', () {
      final text = 'Total 10.00\nTotal 20.00';
      expect(extractAmount(text, languageProfiles['en']!), 20.0);
    });
  });

  group('extractAmount - no keyword fallback', () {
    test('IT: no keyword, plausible maximum wins (excludes > 1,000,000)', () {
      final text = 'Articolo 12,50\nArticolo 99,90\nCodice 9999999,00';
      expect(extractAmount(text, languageProfiles['it']!), 99.90);
    });

    test('IT: fallback excludes negative-keyword lines from the max', () {
      final text = 'Riga1 12,50\nIva 999999,00\nRiga2 40,00';
      expect(extractAmount(text, languageProfiles['it']!), 40.0);
    });

    test('EN: no numbers at all -> null', () {
      const text = 'No numbers here at all';
      expect(extractAmount(text, languageProfiles['en']!), null);
    });
  });
}
