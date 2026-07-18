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
