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

/// Rightmost parseable number on [lines[index]], or (OCR column layout)
/// on the following line if the keyword line itself has none. The next
/// line is skipped when it matches a negative keyword (`消費税率 10.09%`
/// after a value-less `クレジットカード支払`, misura su foto reali
/// 2026-07-22): the column fallback must not steal from excluded lines.
double? _valueNearLine(
  List<String> lines,
  int index,
  LanguageProfile profile,
) {
  final v = _rightmostValue(lines[index], profile.numberFormat);
  if (v != null) return v;
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

double? _rightmostValue(String line, AmountNumberFormat format) {
  final matches = _numberToken.allMatches(line).toList();
  for (var i = matches.length - 1; i >= 0; i--) {
    if (_isPercentToken(line, matches[i])) continue;
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
  final lowerLines =
      lines.map((l) => _stripSpaces(l).toLowerCase()).toList();

  for (final keyword in profile.totalKeywords) {
    final kw = _stripSpaces(keyword).toLowerCase();
    double? best;
    for (var i = 0; i < lines.length; i++) {
      final lower = lowerLines[i];
      if (!lower.contains(kw)) continue;
      if (_containsAny(lower, profile.negativeKeywords)) continue;
      final value = _valueNearLine(lines, i, profile);
      if (value != null && (best == null || value > best)) {
        best = value;
      }
    }
    if (best != null) return best;
  }
  return null;
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
  r'クレジットカード|クレジット売上|receipt|invoice|customer copy',
);

/// A bare slip number line (`No002`, `No. 99131`) or a date/time-only line:
/// the top of card slips is full of them before the merchant appears.
final RegExp _vendorSlipNoPattern = RegExp(r'^no\.?\s*\d+$', caseSensitive: false);
final RegExp _vendorDateLinePattern = RegExp(r'\d{4}\s*[年/-]\s*\d{1,2}');

/// Label a card slip uses to introduce the merchant name; the value may sit
/// after the label on the same line or on the next one.
final RegExp _vendorLabelPattern = RegExp(r'加盟店名?|ご利用店舗|店舗名');

/// Whether [line] looks like noise rather than a vendor name: an address
/// with a zip code, a VAT number, a phone number, a URL, a document-type
/// header, a slip number / date line, or a line made up almost entirely of
/// digits/punctuation (no letters at all).
bool _isVendorNoiseLine(String line) {
  final lower = _stripSpaces(line).toLowerCase();
  if (_vendorZipPattern.hasMatch(lower)) return true;
  if (_vendorPIvaPattern.hasMatch(lower)) return true;
  if (_vendorTelPattern.hasMatch(line.toLowerCase())) return true;
  if (_vendorUrlPattern.hasMatch(lower)) return true;
  if (_vendorDocTypePattern.hasMatch(lower)) return true;
  if (_vendorSlipNoPattern.hasMatch(lower)) return true;
  if (_vendorDateLinePattern.hasMatch(lower)) return true;
  if (!_vendorLetterPattern.hasMatch(line)) return true;
  // Vendor names never contain `#`: on real photos it shows up in garbled
  // logo lines (`HARD-oF#`, misura 2026-07-22) printed above the clean name.
  if (line.contains('#')) return true;
  return false;
}

final RegExp _vendorLeadingDust = RegExp(r'^[·・.,、。:;\-–—\s]+');
final RegExp _vendorKanaHyphen = RegExp(r'(?<=[ァ-ヺ])-(?=[ァ-ヺ])');
final RegExp _vendorLatinKuchi = RegExp(r'(?<=[A-Za-z])口(?=[A-Za-z])');
final RegExp _vendorStrayLatin = RegExp(r'^[A-Za-z](?=[ァ-ヺ])');

/// Repairs systematic ML Kit glyph errors inside a vendor candidate
/// (misure su foto reali 2026-07-22): leading punctuation dust (`·健太鼓子`),
/// ASCII hyphen where katakana uses the long-vowel mark (`ヨ-クベニマル`),
/// CJK 口 between latin letters (`LAWS口N`), a single stray latin letter
/// glued to a katakana name by the logo above it (`Kヨークベニマル`).
String _cleanVendor(String value) => value
    .trim()
    .replaceFirst(_vendorLeadingDust, '')
    .replaceAll(_vendorKanaHyphen, 'ー')
    .replaceAll(_vendorLatinKuchi, 'O')
    .replaceFirst(_vendorStrayLatin, '')
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
    // slip prints them on the same row (`加盟店名宇都宮MS係員65`).
    value = value.split(RegExp(r'[/／]|係員')).first.trim();
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
  for (final line in lines.take(6)) {
    if (_isVendorNoiseLine(line)) continue;
    final cleaned = _cleanVendor(line);
    if (cleaned.isNotEmpty) return cleaned;
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
