import 'package:csv/csv.dart';

import '../../core/utils/formatters.dart';
import 'trasferta_report.dart';

/// Renders a [TrasfertaReport] to an Excel-IT-friendly CSV: `;` separator,
/// comma decimals, UTF-8 BOM so accents/€ show correctly on open.
class CsvExportService {
  const CsvExportService();

  String build(TrasfertaReport report) {
    final rows = <List<String>>[
      const [
        'Data',
        'Categoria',
        'Fornitore',
        'Importo',
        'Valuta',
        'Importo EUR',
        'Tasso',
        'Note',
      ],
      for (final r in report.righe)
        [
          formatDate(r.data),
          r.categoria.label,
          r.fornitore ?? '',
          _money(r.importo),
          r.valuta,
          r.importoEur == null ? '' : _money(r.importoEur!),
          r.tassoCambio == null ? '' : _rate(r.tassoCambio!),
          r.note ?? '',
        ],
      const <String>[],
      [
        'TOTALE EUR',
        '', '', '', '',
        _money(report.totaleEur),
        '',
        report.countSenzaEur > 0
            ? 'esclude ${report.countSenzaEur} spese non convertite'
            : '',
      ],
    ];
    return const CsvEncoder(
      fieldDelimiter: ';',
      lineDelimiter: '\r\n',
      addBom: true,
    ).convert(rows);
  }

  /// Money as text with a comma decimal, two digits, no thousands separator
  /// (the `;` separator means the comma is safe and Excel-IT reads it as a
  /// number).
  String _money(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  /// Exchange rate keeps its stored precision (rates can be < 0.01).
  String _rate(double value) => value.toString().replaceAll('.', ',');
}
