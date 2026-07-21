import 'package:intl/intl.dart';

import '../constants/currencies.dart';

/// it_IT amount/date formatting. Dates use a fixed dd/MM/yyyy pattern so
/// no locale-data initialization is needed in tests or at startup.
String formatImporto(double value, {int decimalDigits = 2}) =>
    NumberFormat.decimalPatternDigits(
            locale: 'it_IT', decimalDigits: decimalDigits)
        .format(value);

/// Amount with the ISO currency symbol and that currency's decimal digits
/// (JPY has none, KWD has three). Unknown code → the code itself as prefix.
String formatValuta(double value, String codeIso) {
  final currency = Currency.fromCode(codeIso);
  if (currency == null) return '$codeIso ${formatImporto(value)}';
  return '${currency.symbol} '
      '${formatImporto(value, decimalDigits: currency.decimalDigits)}';
}

String formatEur(double value) => formatValuta(value, 'EUR');

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String formatDateRange(DateTime start, DateTime? end) =>
    '${formatDate(start)} – ${end == null ? 'in corso' : formatDate(end)}';
