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
    this.roundingKeywords = const [],
    this.defaultCurrency,
  });

  final String code;
  final List<String> totalKeywords; // lowercase, per priorità
  final List<String> negativeKeywords; // lowercase

  /// Labels of a rounding line that corrects the printed total (JP
  /// `端数処理 ¥-8`): its signed value is added to the keyword total, because
  /// what the customer is charged is total + adjustment.
  final List<String> roundingKeywords;
  final List<ReceiptDatePattern> datePatterns;
  final AmountNumberFormat numberFormat;
  final String? defaultCurrency;
  // ja→JPY, sr→RSD, de→EUR, it→EUR, pl→PLN, en→null
}

final RegExp _dmySlashOrDash = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b');
final RegExp _mdySlash = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b');
final RegExp _dmyDot = RegExp(r'\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b');
// Spaces are optional around every separator: receipts right-align the
// day/month fields (`2026年 7月 5日`).
final RegExp _jaKanjiDate =
    RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日');
final RegExp _jaSlashDate = RegExp(r'\b(\d{4})/(\d{1,2})/(\d{1,2})\b');
// The hyphen is a thin glyph ML Kit sometimes prints twice (`2026-07--24`,
// misura on-device 2026-08-25).
final RegExp _isoDashDate = RegExp(r'\b(\d{4})-{1,2}(\d{1,2})-{1,2}(\d{1,2})\b');
// Second-hand/POS terminals print the year with two digits (`売上 26/07/25`,
// misura su foto reali 2026-08-20, scontrino 駿河屋). Japanese receipts are
// always year-first, so `yy/mm/dd` is unambiguous here — unlike the latin
// profiles, where the same shape would collide with `dd/mm/yy`. The
// lookarounds keep it from matching inside a 4-digit-year date (`2026/07/25`)
// or a longer digit run.
final RegExp _jaShortSlashDate =
    RegExp(r'(?<![\d/])(\d{2})/(\d{1,2})/(\d{1,2})(?![\d/])');

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
    // Most specific first: a receipt that prints both `合計金額` and a bare
    // `計` must resolve on the former. `計` is last because it is a
    // substring of many labels and only wins when nothing better exists
    // (taxi slips print just `計 5520円`).
    totalKeywords: [
      '合計金額',
      'お買上計',
      'お買上げ計',
      '買上金額',
      '取引金額',
      'お会計',
      '合計',
      '総計',
      // Card receipts where every 合計 line is killed by a negative keyword
      // (misure su foto reali 2026-07-22): the card-payment amount and the
      // bare 金額 label are the only clean totals left. Both stay below the
      // explicit total keywords and above the bare 計.
      'クレジット',
      '金額',
      '計',
    ],
    negativeKeywords: [
      '小計',
      'お預り',
      'お預かり',
      'お釣',
      '釣銭',
      '税',
      '点数',
      '対象',
      'ポイント',
      '累計',
      '割引',
      '番号',
      'tel',
      '電話',
      '端数',
    ],
    roundingKeywords: ['端数処理', '端数調整', '端数値引'],
    datePatterns: [
      ReceiptDatePattern(_jaKanjiDate, 'ymd'),
      ReceiptDatePattern(_jaSlashDate, 'ymd'),
      ReceiptDatePattern(_isoDashDate, 'ymd'),
      // Last: a 4-digit year elsewhere on the receipt is always the better
      // reading, so the short form only wins when nothing else matched.
      ReceiptDatePattern(_jaShortSlashDate, 'ymd'),
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
    totalKeywords: ['summe', 'gesamtbetrag', 'gesamt', 'zu zahlen'],
    negativeKeywords: ['zwischensumme', 'mwst', 'rückgeld', 'bar'],
    datePatterns: [ReceiptDatePattern(_dmyDot, 'dmy')],
    numberFormat: AmountNumberFormat.commaDecimal,
    defaultCurrency: 'EUR',
  ),
  'pl': LanguageProfile(
    code: 'pl',
    // Most specific first, as in the japanese profile: a `paragon fiskalny`
    // prints the VAT total (`SUMA PTU`) right above the real one
    // (`SUMA PLN`), so the currency-qualified labels must outrank the bare
    // `suma`/`razem`. `do zapłaty` (what is actually due, i.e. net of any
    // discount) outranks both, and its diacritic-less twin is there because
    // ML Kit reads `ł` as `l` on POS fonts.
    totalKeywords: [
      'suma pln',
      'razem pln',
      'kwota pln',
      'do zapłaty',
      'do zaplaty',
      'razem',
      'suma',
      'łącznie',
      'lacznie',
      'kwota',
    ],
    // `ptu` is the polish VAT label: it kills `SUMA PTU` without touching
    // `SUMA PLN`, because a keyword only owns the numbers printed before the
    // next negative label on its own line. `gotówka`/`reszta` are the cash
    // tendered and the change, never the total.
    negativeKeywords: [
      // Subtotals, which both contain `suma`: the keyword only loses to a
      // negative that overlaps it (`podsuma`) or that follows it on the same
      // line (`suma częściowa`), so the real `SUMA` line still wins.
      'podsuma',
      'częściowa',
      'czesciowa',
      'ptu',
      'vat',
      'podatek',
      'stawka',
      'zwolniona',
      'reszta',
      'gotówka',
      'gotowka',
      'rabat',
      'w tym',
      'nip',
      'tel',
    ],
    // Polish receipts print the fiscal date ISO-first (`2026-07-14`); the
    // dotted and slashed day-first forms show up on non-fiscal slips.
    datePatterns: [
      ReceiptDatePattern(_isoDashDate, 'ymd'),
      ReceiptDatePattern(_dmyDot, 'dmy'),
      ReceiptDatePattern(_dmySlashOrDash, 'dmy'),
    ],
    numberFormat: AmountNumberFormat.commaDecimal,
    defaultCurrency: 'PLN',
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
