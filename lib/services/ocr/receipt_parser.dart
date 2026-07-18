import 'language_profiles.dart';

/// Matches a run of digits/separators/currency symbols that contains at
/// least one digit is checked by [parseAmountToken] itself; this pattern
/// just delimits candidate tokens inside a line.
final RegExp _numberToken = RegExp(r'[0-9.,€$¥£]+');

const double _maxPlausibleAmount = 1000000;

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
/// on the following line if the keyword line itself has none.
double? _valueNearLine(List<String> lines, int index, AmountNumberFormat format) {
  final v = _rightmostValue(lines[index], format);
  if (v != null) return v;
  if (index + 1 < lines.length) {
    return _rightmostValue(lines[index + 1], format);
  }
  return null;
}

double? _rightmostValue(String line, AmountNumberFormat format) {
  final matches = _numberToken.allMatches(line).toList();
  for (var i = matches.length - 1; i >= 0; i--) {
    final v = parseAmountToken(matches[i].group(0)!, format);
    if (v != null) return v;
  }
  return null;
}

bool _containsAny(String lowerLine, List<String> keywords) =>
    keywords.any((k) => lowerLine.contains(k.toLowerCase()));

/// Extracts the total amount from raw OCR [text] using [profile]'s
/// keywords and number format. Lines matching a negative keyword (e.g.
/// subtotal, tax, change) are never used as the total, even if they also
/// contain a total keyword as a substring (e.g. "subtotale" / "totale").
double? extractAmount(String text, LanguageProfile profile) {
  final lines = text.split('\n');
  final lowerLines = lines.map((l) => l.toLowerCase()).toList();

  for (final keyword in profile.totalKeywords) {
    final kw = keyword.toLowerCase();
    double? best;
    for (var i = 0; i < lines.length; i++) {
      final lower = lowerLines[i];
      if (!lower.contains(kw)) continue;
      if (_containsAny(lower, profile.negativeKeywords)) continue;
      final value = _valueNearLine(lines, i, profile.numberFormat);
      if (value != null && (best == null || value > best)) {
        best = value;
      }
    }
    if (best != null) return best;
  }

  double? maxPlausible;
  for (var i = 0; i < lines.length; i++) {
    if (_containsAny(lowerLines[i], profile.negativeKeywords)) continue;
    for (final match in _numberToken.allMatches(lines[i])) {
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

/// Whether [line] looks like noise rather than a vendor name: an address
/// with a zip code, a VAT number, a phone number, a URL, or a line made up
/// almost entirely of digits/punctuation (no letters at all).
bool _isVendorNoiseLine(String line) {
  final lower = line.toLowerCase();
  if (_vendorZipPattern.hasMatch(lower)) return true;
  if (_vendorPIvaPattern.hasMatch(lower)) return true;
  if (_vendorTelPattern.hasMatch(lower)) return true;
  if (_vendorUrlPattern.hasMatch(lower)) return true;
  if (!_vendorLetterPattern.hasMatch(line)) return true;
  return false;
}

/// Extracts the vendor/merchant name from raw OCR [text]: the first of the
/// first three non-empty lines that doesn't look like noise (see
/// [_isVendorNoiseLine]), trimmed. Returns `null` if none survive.
String? extractVendor(String text) {
  final candidateLines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(3);
  for (final line in candidateLines) {
    if (!_isVendorNoiseLine(line)) return line;
  }
  return null;
}
