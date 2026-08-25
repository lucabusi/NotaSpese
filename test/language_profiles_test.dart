import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/language_profiles.dart';

void main() {
  const expectedCurrencies = {
    'it': 'EUR',
    'en': null,
    'ja': 'JPY',
    'sr': 'RSD',
    'de': 'EUR',
    'pl': 'PLN',
  };

  test('all 6 language profiles present', () {
    expect(languageProfiles.keys.toSet(), {'it', 'en', 'ja', 'sr', 'de', 'pl'});
  });

  for (final code in ['it', 'en', 'ja', 'sr', 'de', 'pl']) {
    test('profile "$code" has non-empty keywords/patterns/format', () {
      final profile = languageProfiles[code]!;
      expect(profile.code, code);
      expect(profile.totalKeywords, isNotEmpty);
      expect(profile.negativeKeywords, isNotEmpty);
      expect(profile.datePatterns, isNotEmpty);
      expect(profile.numberFormat, isNotNull);
      expect(profile.defaultCurrency, expectedCurrencies[code]);
    });
  }

  group('detectScript', () {
    test('Japanese text -> ja', () {
      expect(detectScript('合計 1,000円'), 'ja');
    });

    test('Cyrillic text -> sr', () {
      expect(detectScript('УКУПНО 1000 РСД'), 'sr');
    });

    test('Latin text -> null', () {
      expect(detectScript('Total amount due: 42.00'), null);
    });
  });
}
