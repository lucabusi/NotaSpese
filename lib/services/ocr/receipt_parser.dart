import 'language_profiles.dart';
import 'parsed_receipt.dart';

/// Matches a run of digits/separators/currency symbols that contains at
/// least one digit is checked by [parseAmountToken] itself; this pattern
/// just delimits candidate tokens inside a line.
final RegExp _numberToken = RegExp(r'[0-9.,€$¥£]+');

const double _maxPlausibleAmount = 1000000;

final RegExp _spaceChar = RegExp(r'[\s　]+');

/// Normalizes raw OCR text before extraction: full-width ASCII (`５５２０`,
/// `Ｎｏ`) → half-width, ideographic space → plain space, full-width yen
/// (`￥`) → `¥`. Japanese receipts printed by taxi/POS terminals use
/// full-width digits throughout, which otherwise match no number or date
/// pattern at all.
String normalizeOcrText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else if (rune == 0xFFE5) {
      buffer.write('¥');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  // [FIX] ML Kit splits thousands groups after the comma (`¥1, 489`):
  // rejoin only when exactly 3 digits follow, so decimal commas
  // (`1, 50`) are left alone.
  return buffer.toString().replaceAllMapped(
        _splitThousands,
        (m) => '${m.group(1)},${m.group(2)}',
      );
}

final RegExp _splitThousands = RegExp(r'(\d),\s+(\d{3})\b');

/// ML Kit's japanese model systematically reads the `¥` glyph as a `4`
/// attached to the amount (`¥6,775` → `46,775`, misura su foto reali
/// 2026-07-22). Rewrites a leading `4` on a comma-grouped number back to
/// `¥` unless it is part of a longer number or already preceded by `¥`.
/// Only called for CJK text (see [ReceiptParser.parse]): on latin
/// receipts a leading 4 is a legitimate digit.
String fixYenGlyphs(String text) => text.replaceAllMapped(
      _yenAsFour,
      (m) => '¥${m.group(1)}',
    );

final RegExp _yenAsFour = RegExp(r'(?<![0-9¥.,])4(\d{1,3}(?:,\d{3})+)');

/// Line with every space removed, so keyword matching survives the
/// letter-spacing receipts use for emphasis (`合  計`, `小 計 額`).
String _stripSpaces(String line) => line.replaceAll(_spaceChar, '');

/// Parses a single amount-like token (may have a currency symbol attached,
/// e.g. `€12,50` or `¥1,200`) using the given [format] to decide which
/// separator is the decimal point. Returns `null` if [token] has no digits.
double? parseAmountToken(String token, AmountNumberFormat format) {
  final cleaned = token.replaceAll(RegExp(r'[^0-9.,-]'), '');
  if (!cleaned.contains(RegExp(r'[0-9]'))) return null;

  String normalized;
  switch (format) {
    case AmountNumberFormat.commaDecimal:
      normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
      break;
    case AmountNumberFormat.dotDecimal:
      normalized = cleaned.replaceAll(',', '');
      break;
    case AmountNumberFormat.integerOnly:
      normalized = cleaned.replaceAll(',', '').replaceAll('.', '');
      break;
  }
  return double.tryParse(normalized);
}

/// [line] with every space dropped, plus the index each surviving character
/// had in [line], so keyword positions found on the compacted text can be
/// mapped back onto the original (where the numbers still are).
({String compact, List<int> origIndex}) _compact(String line) {
  final buffer = StringBuffer();
  final origIndex = <int>[];
  for (var i = 0; i < line.length; i++) {
    if (_spaceChar.hasMatch(line[i])) continue;
    buffer.write(line[i]);
    origIndex.add(i);
  }
  return (compact: buffer.toString().toLowerCase(), origIndex: origIndex);
}

/// Value belonging to [keyword] on `lines[index]`, or `null` when that line
/// carries no total for it.
///
/// The keyword owns the numbers printed after it and before the next
/// negative-keyword label on the same line, instead of the whole line: ML Kit
/// merges two printed rows into one whenever they overlap vertically, so a
/// legitimate `合計 ¥880` routinely arrives glued to an `お預り ¥1,000`
/// (misura su testo degradato 2026-08-20) and rejecting the whole line loses
/// the total. A negative label that overlaps the keyword itself (`小計` for
/// the bare `計`) still kills it.
///
/// When the line holds no number at all the value is taken from the following
/// line (ML Kit column layout), which is skipped if it matches a negative
/// keyword (`消費税率 10.09%` after a value-less `クレジットカード支払`,
/// misura su foto reali 2026-07-22).
double? _valueForKeyword(
  List<String> lines,
  int index,
  String keyword,
  LanguageProfile profile,
) {
  final line = lines[index];
  final c = _compact(line);
  if (!c.compact.contains(keyword)) return null;

  final negatives = <({int start, int end})>[];
  for (final negative in profile.negativeKeywords) {
    final n = _stripSpaces(negative).toLowerCase();
    if (n.isEmpty) continue;
    for (var at = c.compact.indexOf(n); at >= 0;
        at = c.compact.indexOf(n, at + 1)) {
      negatives.add((start: at, end: at + n.length));
    }
  }

  double? best;
  for (var ks = c.compact.indexOf(keyword); ks >= 0;
      ks = c.compact.indexOf(keyword, ks + 1)) {
    final ke = ks + keyword.length;
    if (negatives.any((n) => n.start < ke && n.end > ks)) continue;

    var scopeEnd = c.compact.length;
    for (final n in negatives) {
      if (n.start >= ke && n.start < scopeEnd) scopeEnd = n.start;
    }
    final from = ke < c.origIndex.length ? c.origIndex[ke] : line.length;
    final to = scopeEnd < c.origIndex.length ? c.origIndex[scopeEnd] : line.length;
    final value = _rightmostValue(line.substring(from, to), profile.numberFormat);
    if (value != null && (best == null || value > best)) best = value;
  }
  if (best != null) return best;

  // Column layout: the amounts sit on the next recognized line. A document
  // title (`クレジットカード売上票`) is never a label, so it must not adopt
  // the line below it — which on card slips is the date/time row, and would
  // hand back the clock as the total (misura su testo degradato 2026-08-20).
  if (_rightmostValue(line, profile.numberFormat) != null) return null;
  if (_vendorDocTypePattern.hasMatch(_stripSpaces(line).toLowerCase())) {
    return null;
  }
  if (index + 1 < lines.length &&
      !_containsAny(
          _stripSpaces(lines[index + 1]).toLowerCase(),
          profile.negativeKeywords)) {
    return _rightmostValue(lines[index + 1], profile.numberFormat);
  }
  return null;
}

/// Whether the number [match] is a rate rather than an amount, i.e. it is
/// immediately followed by a percent sign (`10%割引`, `消費税率 10.0%`).
bool _isPercentToken(String line, RegExpMatch match) =>
    match.end < line.length && line[match.end] == '%';

final RegExp _latinLetter = RegExp(r'[A-Za-z_]');

final RegExp _codeBodyChar = RegExp(r'[A-Za-z0-9_]');

/// Whether the latin letter at [index] is really a `¥` sign misread by ML Kit
/// (`合計 F544`, `お買上計 Y1,626`): misura on-device 2026-08-25, 13 scontrini
/// su 53. A currency glyph stands alone right before the digits, while a code
/// prefix is part of a longer alphanumeric run (`ARC00`). The registration
/// number `T9021001013831` is also a lone letter, hence the restriction to the
/// two glyphs ML Kit actually substitutes for `¥`.
bool _isYenGlyphLetter(String line, int index) =>
    (line[index] == 'Y' || line[index] == 'F') &&
    (index == 0 || !_codeBodyChar.hasMatch(line[index - 1]));

/// Whether the number [match] is the digit tail of an alphanumeric code
/// (`ARC00`, `No.7837754670001`, `T9021001013831`, `SEQ No 01`) rather than an
/// amount: on receipts an amount is always separated from its label, while
/// terminal/approval/registration codes glue their digits to latin letters.
bool _isCodeTail(String line, RegExpMatch match) =>
    match.start > 0 &&
    _latinLetter.hasMatch(line[match.start - 1]) &&
    !_isYenGlyphLetter(line, match.start - 1);

/// Whether [match] is one half of a clock reading (`17:38`): the amount
/// extractor must not mistake a printed time for a total. A colon that merely
/// separates a label from its value (`合計:1,234`) is not a clock, hence the
/// digit on the far side of the colon.
bool _isClockToken(String line, RegExpMatch match) {
  if (match.start >= 2 &&
      line[match.start - 1] == ':' &&
      RegExp(r'\d').hasMatch(line[match.start - 2])) {
    return true;
  }
  return match.end + 1 < line.length &&
      line[match.end] == ':' &&
      RegExp(r'\d').hasMatch(line[match.end + 1]);
}

double? _rightmostValue(String line, AmountNumberFormat format) {
  final matches = _numberToken.allMatches(line).toList();
  for (var i = matches.length - 1; i >= 0; i--) {
    if (_isPercentToken(line, matches[i])) continue;
    if (_isCodeTail(line, matches[i])) continue;
    if (_isClockToken(line, matches[i])) continue;
    final v = parseAmountToken(matches[i].group(0)!, format);
    if (v != null) return v;
  }
  return null;
}

bool _containsAny(String lowerLine, List<String> keywords) =>
    keywords.any((k) => lowerLine.contains(k.toLowerCase()));

/// Keyword-tier pass of [extractAmount]: the total amount found on a line
/// matching one of [profile]'s total keywords (or the following line, OCR
/// column layout), skipping lines that also match a negative keyword.
/// Returns `null` if no keyword line yields a value, so the caller knows to
/// fall back to [_amountViaFallback] — this is also how the parser's scorer
/// tells the keyword path from the fallback-max path without re-implementing
/// the matching logic.
double? _amountViaKeywords(String text, LanguageProfile profile) {
  final lines = text.split('\n');

  for (final keyword in profile.totalKeywords) {
    final kw = _stripSpaces(keyword).toLowerCase();
    double? best;
    for (var i = 0; i < lines.length; i++) {
      final value = _valueForKeyword(lines, i, kw, profile);
      if (value != null && (best == null || value > best)) {
        best = value;
      }
    }
    if (best != null) {
      final adjustment = _roundingAdjustment(text, profile);
      if (adjustment != null && best + adjustment > 0) return best + adjustment;
      return best;
    }
  }
  return null;
}

/// Signed value of a rounding line (`端数処理 ¥-8`), where the minus sign may
/// sit on either side of the currency glyph. `null` when the line carries no
/// number at all.
final RegExp _signedAmount =
    RegExp(r'(-|−|–|▲|△)?\s*[¥￥]?\s*(-|−|–)?\s*(\d[\d,]*)');

/// Sum of every rounding-line adjustment in [text] (`端数処理 ¥-8` → -8), or
/// `null` when [profile] declares no rounding keywords or none is present.
/// Applied only to the keyword total: what the card is charged is the printed
/// total plus this correction.
double? _roundingAdjustment(String text, LanguageProfile profile) {
  if (profile.roundingKeywords.isEmpty) return null;
  double? total;
  for (final line in text.split('\n')) {
    final stripped = _stripSpaces(line);
    if (!profile.roundingKeywords.any(stripped.contains)) continue;
    final labelEnd = profile.roundingKeywords
        .map((k) => stripped.indexOf(k) + k.length)
        .where((i) => i > 0)
        .reduce((a, b) => a > b ? a : b);
    final match = _signedAmount.firstMatch(stripped.substring(labelEnd));
    if (match == null) continue;
    final value = double.tryParse(match.group(3)!.replaceAll(',', ''));
    if (value == null || value == 0) continue;
    final negative = match.group(1) != null || match.group(2) != null;
    total = (total ?? 0) + (negative ? -value : value);
  }
  return total;
}

/// Fallback-max pass of [extractAmount]: the largest plausible number found
/// anywhere in [text] outside lines matching one of [profile]'s negative
/// keywords, used when no total keyword line yields a value.
double? _amountViaFallback(String text, LanguageProfile profile) {
  final lines = text.split('\n');
  final lowerLines =
      lines.map((l) => _stripSpaces(l).toLowerCase()).toList();

  double? maxPlausible;
  for (var i = 0; i < lines.length; i++) {
    if (_containsAny(lowerLines[i], profile.negativeKeywords)) continue;
    for (final match in _numberToken.allMatches(lines[i])) {
      if (_isPercentToken(lines[i], match)) continue;
      if (_isCodeTail(lines[i], match)) continue;
      if (_isClockToken(lines[i], match)) continue;
      final v = parseAmountToken(match.group(0)!, profile.numberFormat);
      if (v != null &&
          v > 0 &&
          v <= _maxPlausibleAmount &&
          (maxPlausible == null || v > maxPlausible)) {
        maxPlausible = v;
      }
    }
  }
  return maxPlausible;
}

/// Extracts the total amount from raw OCR [text] using [profile]'s
/// keywords and number format. Lines matching a negative keyword (e.g.
/// subtotal, tax, change) are never used as the total, even if they also
/// contain a total keyword as a substring (e.g. "subtotale" / "totale").
double? extractAmount(String text, LanguageProfile profile) =>
    _amountViaKeywords(text, profile) ?? _amountViaFallback(text, profile);

const int _maxPlausibleDateAgeDays = 730;

/// Builds a [DateTime] from a date [match] given its component [order],
/// or `null` if the resulting date is not a real calendar date (e.g. month
/// 18 from misreading a `dd/MM` pattern as `MM/dd`).
DateTime? _buildDate(RegExpMatch match, String order) {
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  final c = int.parse(match.group(3)!);
  int day;
  int month;
  int year;
  switch (order) {
    case 'mdy':
      month = a;
      day = b;
      year = c;
      break;
    case 'ymd':
      year = a;
      month = b;
      day = c;
      break;
    case 'dmy':
    default:
      day = a;
      month = b;
      year = c;
      break;
  }
  // Two-digit years (`26/07/25`) are this century: receipts older than the
  // plausibility window are dropped by [extractDate] anyway.
  if (year < 100) year += 2000;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Extracts the receipt date from raw OCR [text] using [profile]'s date
/// patterns, tried in order. Within each pattern, matches are tried in
/// order of appearance; a match that parses to an implausible date (in the
/// future, or more than [_maxPlausibleDateAgeDays] in the past relative to
/// [now]) is skipped in favor of the next match. Returns `null` if no
/// pattern yields a plausible date. [now] is injectable for tests.
DateTime? extractDate(String text, LanguageProfile profile, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  final minDate = effectiveNow.subtract(
    const Duration(days: _maxPlausibleDateAgeDays),
  );
  for (final pattern in profile.datePatterns) {
    for (final match in pattern.regex.allMatches(text)) {
      final date = _buildDate(match, pattern.order);
      if (date == null) continue;
      if (date.isAfter(effectiveNow)) continue;
      if (date.isBefore(minDate)) continue;
      return date;
    }
  }
  return null;
}

final RegExp _vendorZipPattern = RegExp(r'\d{5}');
final RegExp _vendorPIvaPattern = RegExp(r'p\.?\s?iva');
final RegExp _vendorTelPattern = RegExp(r'\btel\b|\btelefono\b|\btelephone\b|\bphone\b');
final RegExp _vendorUrlPattern = RegExp(r'www\.|http');
final RegExp _vendorLetterPattern = RegExp(r'\p{L}', unicode: true);

/// Slip/document-type headers printed above the merchant name (receipt,
/// credit-card sales slip, customer copy, …) — never a vendor name.
final RegExp _vendorDocTypePattern = RegExp(
  r'領収書|領収証|レシート|売上票|利用票|お買上票|お客様控|お客さま控|控え|'
  r'明細|クレジットカード|クレジット売上|receipt|invoice|customer copy|'
  r'credit card|sales slip',
);

/// End of a document-type header, so a name merged after it can be recovered
/// (`［領収書］ 九 宇都宮駅西口店`).
final RegExp _vendorDocTypeTail = RegExp(
  r'(領収書|領収証|レシート|売上票|利用票|お買上票|明細書?)[］\]＞>」』\s]*',
);

/// The courtesy line receipts open with (`お買い上げありがとうございます！`):
/// it can sit between the document header and the merchant name (misura su
/// foto reali 2026-08-20, scontrino Treasure Factory).
final RegExp _vendorCourtesyPattern = RegExp(
  r'ありがとうござ|いらっしゃいませ|またのご来店|ご来店誠に|thank you',
);

/// The blank the cashier would hand-write the customer's name into, printed
/// as a rule of fill characters closed by an honorific (`＿＿＿＿＿様`,
/// `______ 御中`): it sits above the merchant name on 領収書-style receipts
/// (misura su foto reali 2026-08-20, scontrini Treasure Factory / MEGA).
final RegExp _vendorNameBlankPattern =
    RegExp(r'^[_＿\-−ー–—\s]*(様|さま|御中)$');

/// A line that is nothing but a shop-category word: the letterhead prints it
/// above the brand (`SUPERMARKET` over 成城石井, misura su foto reali
/// 2026-08-20). Matched only when it is the whole line, so real names that
/// merely contain the word (`CAPCOM STORE Tokyo`) are untouched.
final RegExp _vendorCategoryOnlyPattern = RegExp(
  r'^(supermarket|super\s*market|market|store|shop|restaurant|'
  r'drug\s*store|convenience\s*store|スーパー|ストア|マーケット)$',
  caseSensitive: false,
);

/// A bare slip number line (`No002`, `No. 99131`) or a date/time-only line:
/// the top of card slips is full of them before the merchant appears.
final RegExp _vendorSlipNoPattern = RegExp(r'^no\.?\s*\d+$', caseSensitive: false);
final RegExp _vendorDateLinePattern = RegExp(r'\d{4}\s*[年/-]\s*\d{1,2}');

/// Label a card slip uses to introduce the merchant name; the value may sit
/// after the label on the same line or on the next one. `カ盟店名` is ML
/// Kit misreading 加 (kanji) as カ (katakana) on this exact fixed phrase
/// (misura su foto reali 2026-07-22, scontrino taxi).
final RegExp _vendorLabelPattern = RegExp(r'[加カ]盟店名?|ご利用店舗|店舗名');

/// Whether [line] looks like noise rather than a vendor name: an address
/// with a zip code, a VAT number, a phone number, a URL, a document-type
/// header, a slip number / date line, or a line made up almost entirely of
/// digits/punctuation (no letters at all).
bool _isVendorNoiseLine(String rawLine) {
  // Punctuation dust in front of the line must not hide what the line is
  // (`·________様` is still the customer-name blank).
  final line = rawLine.replaceFirst(_vendorLeadingDust, '');
  final lower = _stripSpaces(line).toLowerCase();
  if (_vendorZipPattern.hasMatch(lower)) return true;
  if (_vendorPIvaPattern.hasMatch(lower)) return true;
  if (_vendorTelPattern.hasMatch(line.toLowerCase())) return true;
  if (_vendorUrlPattern.hasMatch(lower)) return true;
  if (_vendorDocTypePattern.hasMatch(lower)) return true;
  if (_vendorCourtesyPattern.hasMatch(lower)) return true;
  if (_vendorSlipNoPattern.hasMatch(lower)) return true;
  if (_vendorNameBlankPattern.hasMatch(lower)) return true;
  if (_vendorCategoryOnlyPattern.hasMatch(line.trim())) return true;
  if (_vendorDateLinePattern.hasMatch(lower)) return true;
  if (_vendorAddressPattern.hasMatch(line)) return true;
  // The line IS a metadata field, not a name followed by one.
  final field = _vendorFieldStart.firstMatch(line);
  if (field != null && field.start == 0) return true;
  // A priced line is an item, never the letterhead.
  if (_vendorPricedLinePattern.hasMatch(line)) return true;
  if (!_vendorLetterPattern.hasMatch(line)) return true;
  // Vendor names never contain `#`: on real photos it shows up in garbled
  // logo lines (`HARD-oF#`, misura 2026-07-22) printed above the clean name.
  if (line.contains('#')) return true;
  return false;
}

/// The merchant name salvaged from the head of a noise [line]: after a row
/// merge the name keeps its own line but a metadata field is appended to it
/// (`かわらや宇都宮店 〒3200801`, `あなたのお店 登録番号:T78…`, misura su
/// testo degradato 2026-08-20). Returns `null` when the line starts with the
/// field itself, i.e. there is no name in front of it.
/// End of the courtesy sentence a receipt opens with, so what the row merge
/// glued AFTER it can be recovered (`お買い上げありがとうございます！
/// トレジャーファクトリー…`).
final RegExp _vendorCourtesyTail = RegExp(
  r'(?:ありがとうござ[いういまうすしたま]*|いらっしゃいませ|'
  r'またのご来店\S*)[。．,、!！\s]*',
);

/// The merchant name salvaged from the tail of a courtesy or document-header
/// line: the mirror of [_vendorBeforeField], for the case where the merge put
/// the name second.
String? _vendorAfterCourtesy(String line) {
  for (final pattern in [_vendorCourtesyTail, _vendorDocTypeTail]) {
    final match = pattern.firstMatch(line);
    if (match == null || match.end >= line.length) continue;
    final tail = _cleanVendor(line.substring(match.end));
    if (!_isBadSalvage(tail)) return tail;
  }
  return null;
}

/// Whether [fragment] cannot be the merchant name salvaged out of a merged
/// row: too short, no letters, a bare terminal/register id, or noise in its
/// own right.
bool _isBadSalvage(String fragment) =>
    fragment.length < 2 ||
    !_vendorLetterPattern.hasMatch(fragment) ||
    _vendorCodeOnlyPattern.hasMatch(fragment) ||
    _isVendorNoiseLine(fragment);

String? _vendorBeforeField(String line) {
  final match = _vendorFieldStart.firstMatch(line);
  if (match == null || match.start == 0) return null;
  final head = _cleanVendor(line.substring(0, match.start));
  return _isBadSalvage(head) ? null : head;
}

final RegExp _vendorLeadingDust = RegExp(r'^[·・.,、。:;\-–—\s]+');
final RegExp _vendorKanaHyphen = RegExp(r'(?<=[ァ-ヺ])-(?=[ァ-ヺ])');
// A run, not a single glyph: ML Kit reads every O of `BOOKOFF` as 口, so the
// inner ones have no latin neighbour on both sides (misura 2026-08-20).
final RegExp _vendorLatinKuchi = RegExp(r'(?<=[A-Za-z])口+(?=[A-Za-z])');
// Any CJK, not just katakana, and tolerating the punctuation dust that can
// land between the two (`K·ハードオフ…`).
final RegExp _vendorStrayLatin =
    RegExp(r'^[A-Za-z][·・]?(?=[ぁ-ゟァ-ヺ一-鿿])');
/// A line carrying a price (`ゲームソフト ¥1,800込`, `お通し 398円`): it is an
/// item row, so it is never the letterhead — a guard for the case where the
/// merchant line has been merged away entirely.
final RegExp _vendorPricedLinePattern =
    RegExp(r'[¥￥]\s?\d|\d[\d,]*\s?[込円]');
/// A run of separator dashes merged onto the name (`ユニオン コマース ----`).
final RegExp _vendorTrailingRule = RegExp(r'[\s]*[-–—─=＝*＊]{3,}[\s]*$');

/// A short mixed letters-and-digits token (`REG02`, `DF5D`, `8F19`): a
/// register/terminal id, never a shop name. Only ever applied to a fragment
/// salvaged out of a merged row — a letterhead standing on its own may well
/// be an all-caps brand with a digit in it.
final RegExp _vendorCodeOnlyPattern =
    RegExp(r'^(?=.*[A-Z])(?=.*\d)[A-Z0-9_.\-]{2,6}$');
// Anywhere, not just at the end: after a row merge the garbled logo sits in
// front of the name it was merged with (`HARD·OFF# ·ハードオフ…`).
final RegExp _vendorGarbleMark = RegExp(r'[#＃]+');
/// Punctuation dust — and the stray logo letter that comes with it — at the
/// start of the second half of a merged row (`CAPCOM ·STORE`,
/// `HARD·OFF K·ハードオフ…`), where [_vendorLeadingDust] cannot reach.
final RegExp _vendorInnerDust =
    RegExp(r'\s+(?:[A-Za-z](?=[·・]))?[·・]+\s*|\s+[A-Za-z](?=[ぁ-ゟァ-ヺ一-鿿])');
/// Latin letters spaced out for emphasis on the letterhead (`S T O R E`),
/// the same trick receipts use on labels (`合  計`).
final RegExp _vendorLetterSpacing = RegExp(r'\b(?:[A-Za-z] ){2,}[A-Za-z]\b');
/// A lone latin letter left dangling at the end of a name: the stray letter
/// the logo glues to the next line (`Kお取替…`) stays behind when the merged
/// field is cut away (misura su testo degradato 2026-08-20).
final RegExp _vendorTrailingStray = RegExp(r'\s+[A-Za-z]$');

/// Where a metadata field starts inside a line: the merchant name and the
/// field printed under it end up on the same line whenever ML Kit merges two
/// vertically overlapping rows, so everything from here on is not the name.
final RegExp _vendorFieldStart = RegExp(
  r'〒|登録番号|登録事業者番号|事業者番号|端末番号|端末取引|伝票番号|'
  r'店コード|本社|レジ|担当|スタッフ|係員|承認番号|会員番号|取引No|'
  r'電話|☎|\btel\b|https?://|www\.|'
  r'[^\s]{2,3}[都道府県][^\s]{0,6}[市区郡]|'
  r'\d{2,4}[-−]\d{2,4}[-−]\d{4}|'
  // The store-policy sentence printed under the letterhead
  // (`ヨークベニマル お取替・返品の際は…`). Greetings are NOT cut points:
  // they make the whole line noise (see [_vendorCourtesyPattern]), and their
  // own polite prefix (`お買い上げ`ありがとう…) must not survive as a name.
  r'お取替|お取り替え|返品',
  caseSensitive: false,
);

/// English sub-label a card slip prints next to the japanese one
/// (`加盟店名 PIYO PIZZA` / `MERCHANT`): after a row merge it lands right
/// after the value.
final RegExp _vendorSlipLatinLabel = RegExp(
  r'\s+(MERCHANT|STORE\s+PHONE|CUSTOMER|TERMINAL|CARD\s+COMPANY|SLIP|'
  r'TRANSACTION|APPROVAL|PAYMENT|PRODUCT|ACCOUNT|EXPIRY|APPLICATION|'
  r'TOTAL|DATE)\b',
);

/// Street address (`栃木県宇都宮市…`, `東京都渋谷区…`, `大通り3-2-1`), which
/// after a row merge follows the shop name on the same line — or stands alone
/// once the name has been merged away.
final RegExp _vendorAddressPattern = RegExp(
  r'[^\s]{2,3}[都道府県][^\s]{0,6}[市区郡]|丁目|〒|通り\s*\d|番町\s*\d|'
  r'^\s*\S*\d+[-−]\d+[-−]\d+\s*$',
);

/// Repairs systematic ML Kit glyph errors inside a vendor candidate
/// (misure su foto reali 2026-07-22): leading punctuation dust (`·健太鼓子`),
/// ASCII hyphen where katakana uses the long-vowel mark (`ヨ-クベニマル`),
/// CJK 口 between latin letters (`LAWS口N`), a single stray latin letter
/// glued to a katakana name by the logo above it (`Kヨークベニマル`).
String _cleanVendor(String value) => value
    .trim()
    .replaceFirst(_vendorLeadingDust, '')
    .replaceAll(_vendorKanaHyphen, 'ー')
    .replaceAllMapped(_vendorLatinKuchi, (m) => 'O' * m.group(0)!.length)
    .replaceFirst(_vendorStrayLatin, '')
    .replaceFirst(_vendorLeadingDust, '')
    .replaceAll(_vendorGarbleMark, '')
    .replaceFirst(_vendorTrailingRule, '')
    .replaceAll(_vendorInnerDust, ' ')
    .replaceAllMapped(
        _vendorLetterSpacing, (m) => m.group(0)!.replaceAll(' ', ''))
    .replaceFirst(_vendorTrailingStray, '')
    .trim();

/// Merchant name taken from an explicit `加盟店名` (merchant name) label,
/// which card slips print instead of a letterhead: the text after the label
/// on the same line, else the next non-empty line. Trailing operator fields
/// (`／係員473`) are cut off.
String? _vendorFromLabel(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final match = _vendorLabelPattern.firstMatch(lines[i]);
    if (match == null) continue;
    var value = lines[i].substring(match.end).replaceFirst(RegExp(r'^[:：\s]+'), '');
    if (value.trim().isEmpty && i + 1 < lines.length) {
      value = lines[i + 1];
    }
    // Trailing operator fields may arrive without the `/` separator when the
    // slip prints them on the same row (`加盟店名宇都宮MS係員65`), and the
    // english sub-label of the next row lands here after a row merge
    // (`加盟店名 PIYO PIZZA MERCHANT`).
    value = value.split(RegExp(r'[/／]|係員')).first;
    value = value.split(_vendorSlipLatinLabel).first.trim();
    // The row merge can also glue the shop's phone/address to the labelled
    // value (`加盟店 …` → `CAPCOM STORE Tokyo TEL:03-6455-0420`).
    value = _vendorBeforeField(value) ?? value;
    if (value.isNotEmpty && _vendorLetterPattern.hasMatch(value)) return value;
  }
  return null;
}

/// Extracts the vendor/merchant name from raw OCR [text]: an explicit
/// merchant label if present (see [_vendorFromLabel]), else the first of the
/// first six non-empty lines that doesn't look like noise (see
/// [_isVendorNoiseLine]), trimmed. The window is six lines because slips
/// print several document-type/number lines above the merchant name.
/// Returns `null` if none survive.
String? extractVendor(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final labelled = _vendorFromLabel(lines);
  if (labelled != null) return _cleanVendor(labelled);
  final window = lines.take(6).toList();
  for (final line in window) {
    if (_isVendorNoiseLine(line)) {
      // A merged row keeps the name next to whatever made the line noisy:
      // take the head in front of a metadata field, or the tail after a
      // courtesy sentence, rather than skipping the name altogether.
      final salvaged = _vendorBeforeField(line) ?? _vendorAfterCourtesy(line);
      if (salvaged != null) return salvaged;
      continue;
    }
    // Even a line that is not noise as a whole may carry a merged field after
    // the name (`DiPUNTO宇都宮駅前店  028-600-3888`): keep only the head.
    final cleaned = _vendorBeforeField(line) ?? _cleanVendor(line);
    if (cleaned.isNotEmpty) return cleaned;
  }
  // Last resort: every candidate was noise, which on these receipts means the
  // only name printed is the garbled logo line (`bariSheep#`). A repaired
  // logo beats no vendor at all.
  for (final line in window) {
    if (!line.contains('#') && !line.contains('＃')) continue;
    final cleaned = _cleanVendor(line);
    if (cleaned.isNotEmpty && !_isVendorNoiseLine(cleaned)) return cleaned;
  }
  return null;
}

final RegExp _chfPattern = RegExp(r'\bCHF\b', caseSensitive: false);
final RegExp _rsdPattern = RegExp(r'дин\.?|\bdin\b|\bRSD\b', caseSensitive: false);

/// Infers the ISO 4217 currency from an explicit symbol/code found in raw
/// OCR [text] (€, £, $, CHF, дин./din/RSD, ¥/円). Returns `null` if none is
/// present, so the caller falls back to the winning profile's default.
String? inferCurrencyFromText(String text) {
  if (text.contains('€')) return 'EUR';
  if (text.contains('£')) return 'GBP';
  if (text.contains('\$')) return 'USD';
  if (_chfPattern.hasMatch(text)) return 'CHF';
  if (_rsdPattern.hasMatch(text)) return 'RSD';
  if (text.contains('¥') || text.contains('円')) return 'JPY';
  return null;
}

/// Scores how well [profile] fits [text], given the already-extracted
/// [importo]/[data]/[fornitore] for that profile and whether [importo] (when
/// non-null) came from the keyword path ([viaKeyword]) rather than the
/// fallback-max path: 2 points for a keyword-path amount, 1 for a
/// fallback-path amount, 1 for a plausible date, 1 for a vendor, +1 if a
/// total keyword appears anywhere in the text.
int _scoreProfile(
  String text,
  LanguageProfile profile, {
  double? importo,
  required bool viaKeyword,
  DateTime? data,
  String? fornitore,
}) {
  var score = 0;
  if (importo != null) {
    score += viaKeyword ? 2 : 1;
  }
  if (data != null) score += 1;
  if (fornitore != null) score += 1;
  final lower = _stripSpaces(text).toLowerCase();
  if (profile.totalKeywords
      .any((k) => lower.contains(_stripSpaces(k).toLowerCase()))) {
    score += 1;
  }
  return score;
}

/// Candidate profile codes to try, in order: a detected script (ja/sr)
/// always goes first; else [linguaHint] goes first if it names a known
/// profile; the remaining profiles follow in [languageProfiles] order.
List<String> _candidateOrder(String text, String? linguaHint) {
  final order = <String>[];
  final script = detectScript(text);
  if (script != null && languageProfiles.containsKey(script)) {
    order.add(script);
  } else if (linguaHint != null && languageProfiles.containsKey(linguaHint)) {
    order.add(linguaHint);
  }
  for (final code in languageProfiles.keys) {
    if (!order.contains(code)) order.add(code);
  }
  return order;
}

/// Parses raw OCR [text] into a [ParsedReceipt]: tries [LanguageProfile]
/// candidates (script detection, then [linguaHint], then every other
/// profile), scores each one's extraction, and keeps the best (ties go to
/// whichever was tried first). Currency is an explicit symbol/code found in
/// the text, else the winning profile's default. Any internal failure
/// yields an empty [ParsedReceipt] rather than throwing. The engine is
/// always [OcrEngine.mlkit]; callers that used the Claude fallback should
/// `copyWith(engine: OcrEngine.claude)`.
class ReceiptParser {
  ParsedReceipt parse(String rawText, {String? linguaHint}) {
    var text = normalizeOcrText(rawText);
    // Yen-glyph repair only makes sense on japanese receipts.
    if (detectScript(text) == 'ja') text = fixYenGlyphs(text);
    try {
      final fornitore = extractVendor(text);
      String? bestCode;
      var bestScore = -1;
      double? bestImporto;
      DateTime? bestData;

      for (final code in _candidateOrder(text, linguaHint)) {
        final profile = languageProfiles[code]!;
        final viaKeywordAmount = _amountViaKeywords(text, profile);
        final importo = viaKeywordAmount ?? _amountViaFallback(text, profile);
        final data = extractDate(text, profile);
        final score = _scoreProfile(
          text,
          profile,
          importo: importo,
          viaKeyword: viaKeywordAmount != null,
          data: data,
          fornitore: fornitore,
        );
        if (score > bestScore) {
          bestScore = score;
          bestCode = code;
          bestImporto = importo;
          bestData = data;
        }
      }

      final winner = languageProfiles[bestCode]!;
      return ParsedReceipt(
        importo: bestImporto,
        valuta: inferCurrencyFromText(text) ?? winner.defaultCurrency,
        data: bestData,
        fornitore: fornitore,
        lingua: bestCode,
        engine: OcrEngine.mlkit,
        rawText: rawText,
      );
    } catch (_) {
      return ParsedReceipt(engine: OcrEngine.mlkit, rawText: rawText);
    }
  }
}
