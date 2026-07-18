/// How amounts are formatted on receipts of a given language, so the
/// parser knows which separator is the decimal point.
enum AmountNumberFormat {
  commaDecimal, // 1.234,56
  dotDecimal, // 1,234.56
  integerOnly, // 1,234 JPY
}

/// A regex for a date format found on receipts, plus the order of its
/// day/month/year components so the parser can build a [DateTime].
class ReceiptDatePattern {
  ReceiptDatePattern(this.regex, this.order);
  final RegExp regex;
  final String order; // 'dmy'|'mdy'|'ymd'
}

/// Per-language hints used to extract the total amount, date and currency
/// from OCR raw text.
class LanguageProfile {
  LanguageProfile({
    required this.code,
    required this.totalKeywords,
    required this.negativeKeywords,
    required this.datePatterns,
    required this.numberFormat,
    this.defaultCurrency,
  });

  final String code;
  final List<String> totalKeywords; // lowercase, per priorità
  final List<String> negativeKeywords; // lowercase
  final List<ReceiptDatePattern> datePatterns;
  final AmountNumberFormat numberFormat;
  final String? defaultCurrency; // ja→JPY, sr→RSD, de→EUR, it→EUR, en→null
}

final RegExp _dmySlashOrDash = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b');
final RegExp _mdySlash = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b');
final RegExp _dmyDot = RegExp(r'\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b');
final RegExp _jaKanjiDate = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日');
final RegExp _jaSlashDate = RegExp(r'\b(\d{4})/(\d{1,2})/(\d{1,2})\b');

final Map<String, LanguageProfile> languageProfiles = {
  'it': LanguageProfile(
    code: 'it',
    totalKeywords: ['totale', 'tot.'],
    negativeKeywords: ['subtotale', 'resto', 'contante', 'iva', 'sconto'],
    datePatterns: [ReceiptDatePattern(_dmySlashOrDash, 'dmy')],
    numberFormat: AmountNumberFormat.commaDecimal,
    defaultCurrency: 'EUR',
  ),
  'en': LanguageProfile(
    code: 'en',
    totalKeywords: ['total', 'amount due', 'balance due'],
    negativeKeywords: ['subtotal', 'change', 'tax', 'cash', 'discount'],
    datePatterns: [
      ReceiptDatePattern(_dmySlashOrDash, 'dmy'),
      ReceiptDatePattern(_mdySlash, 'mdy'),
    ],
    numberFormat: AmountNumberFormat.dotDecimal,
    defaultCurrency: null,
  ),
  'ja': LanguageProfile(
    code: 'ja',
    totalKeywords: ['合計', '総計', 'お会計'],
    negativeKeywords: ['小計', 'お預り', 'お釣', '釣銭', '税'],
    datePatterns: [
      ReceiptDatePattern(_jaKanjiDate, 'ymd'),
      ReceiptDatePattern(_jaSlashDate, 'ymd'),
    ],
    numberFormat: AmountNumberFormat.integerOnly,
    defaultCurrency: 'JPY',
  ),
  'sr': LanguageProfile(
    code: 'sr',
    totalKeywords: ['ukupno', 'укупно', 'za uplatu'],
    negativeKeywords: ['međuzbir', 'povraćaj', 'pdv', 'повраћај'],
    datePatterns: [
      ReceiptDatePattern(_dmySlashOrDash, 'dmy'),
      ReceiptDatePattern(_dmyDot, 'dmy'),
    ],
    numberFormat: AmountNumberFormat.commaDecimal,
    defaultCurrency: 'RSD',
  ),
  'de': LanguageProfile(
    code: 'de',
    totalKeywords: ['summe', 'gesamt', 'gesamtbetrag', 'zu zahlen'],
    negativeKeywords: ['zwischensumme', 'mwst', 'rückgeld', 'bar'],
    datePatterns: [ReceiptDatePattern(_dmyDot, 'dmy')],
    numberFormat: AmountNumberFormat.commaDecimal,
    defaultCurrency: 'EUR',
  ),
};

final RegExp _cjk = RegExp('[぀-ヿ一-鿿]');
final RegExp _cyrillic = RegExp('[Ѐ-ӿ]');

/// Detects the receipt's script family from raw OCR text, to pick the
/// [LanguageProfile] when the trip's language isn't already known.
/// Returns `'ja'` for CJK text, `'sr'` for Cyrillic text, else `null`.
String? detectScript(String text) {
  if (_cjk.hasMatch(text)) return 'ja';
  if (_cyrillic.hasMatch(text)) return 'sr';
  return null;
}
