import 'package:intl/intl.dart';

/// it_IT amount/date formatting. Dates use a fixed dd/MM/yyyy pattern so
/// no locale-data initialization is needed in tests or at startup.
String formatImporto(double value, {int decimalDigits = 2}) =>
    NumberFormat.decimalPatternDigits(
            locale: 'it_IT', decimalDigits: decimalDigits)
        .format(value);

String formatEur(double value) => '€ ${formatImporto(value)}';

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String formatDateRange(DateTime start, DateTime? end) =>
    '${formatDate(start)} – ${end == null ? 'in corso' : formatDate(end)}';
