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

    test('DE: gesamtbetrag outranks generic gesamt', () {
      final text = 'Gesamt 10,00\nGesamtbetrag 55,00';
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

  group('extractDate', () {
    test('IT: dd/MM/yyyy format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Scontrino\nData: 15/07/2026\nTotale 10,00';
      expect(
        extractDate(text, languageProfiles['it']!, now: now),
        DateTime(2026, 7, 15),
      );
    });

    test('EN: MM/dd/yyyy format extracted (day > 12 disambiguates)', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Receipt\n07/16/2026\nTotal 25.00';
      expect(
        extractDate(text, languageProfiles['en']!, now: now),
        DateTime(2026, 7, 16),
      );
    });

    test('JA: yyyy年M月d日 format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'レシート\n2026年7月18日\n合計 1,000円';
      expect(
        extractDate(text, languageProfiles['ja']!, now: now),
        DateTime(2026, 7, 18),
      );
    });

    test('DE: dd.MM.yyyy format extracted', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Quittung\n17.07.2026\nGesamtbetrag 55,00';
      expect(
        extractDate(text, languageProfiles['de']!, now: now),
        DateTime(2026, 7, 17),
      );
    });

    test('future date is rejected, search continues to a plausible one', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Data ordine: 01/01/2027\nData scontrino: 10/07/2026';
      expect(
        extractDate(text, languageProfiles['it']!, now: now),
        DateTime(2026, 7, 10),
      );
    });

    test('date older than 730 days is rejected', () {
      final now = DateTime(2026, 7, 18);
      final text = 'Data: 10/07/2023';
      expect(extractDate(text, languageProfiles['it']!, now: now), null);
    });

    test('no date in text -> null', () {
      final now = DateTime(2026, 7, 18);
      const text = 'Nessuna data qui';
      expect(extractDate(text, languageProfiles['it']!, now: now), null);
    });
  });

  group('extractVendor', () {
    test('first clean line returned trimmed', () {
      const text = '  Bar Centrale  \nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'Bar Centrale');
    });

    test('P.IVA line skipped, next clean line returned', () {
      const text = 'P.IVA 12345678901\nRistorante Da Mario\nVia Roma 1';
      expect(extractVendor(text), 'Ristorante Da Mario');
    });

    test('phone line skipped', () {
      const text = 'Tel: 02-1234567\nFarmacia Centrale\nVia Milano 5';
      expect(extractVendor(text), 'Farmacia Centrale');
    });

    test('CAP (zip) line skipped', () {
      const text = '20100 Milano\nSupermercato Alfa\nVia Torino 2';
      expect(extractVendor(text), 'Supermercato Alfa');
    });

    test('URL line skipped', () {
      const text = 'www.negozio.it\nNegozio Beta\nVia Napoli 3';
      expect(extractVendor(text), 'Negozio Beta');
    });

    test('line of mostly digits/punctuation skipped', () {
      const text = '---***---\nCaffetteria Gamma\nVia Torino 9';
      expect(extractVendor(text), 'Caffetteria Gamma');
    });

    test('only first 3 non-empty lines considered, all noisy -> null', () {
      const text = '12345\nTel: 0212345\nwww.site.it\nVendor Name';
      expect(extractVendor(text), null);
    });

    test('hotel line not discarded by tel pattern (word boundary check)', () {
      const text = 'Hotel Bristol\nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'Hotel Bristol');
    });

    test('phone line still skipped with Tel. prefix', () {
      const text = 'Tel. 02 1234567\nTrattoria da Mario\nVia Torino 8';
      expect(extractVendor(text), 'Trattoria da Mario');
    });

    test('iPhone Store not discarded by phone pattern (word boundary check)', () {
      const text = 'iPhone Store\nVia Roma 1\nCAP 20100';
      expect(extractVendor(text), 'iPhone Store');
    });

    test('empty text -> null', () {
      expect(extractVendor(''), null);
    });
  });
}
