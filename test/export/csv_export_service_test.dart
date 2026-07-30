import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/csv_export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip() => Trasferta(
      id: 1,
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  test('header row and BOM prefix', () {
    final csv = const CsvExportService().build(
      TrasfertaReport.build(_trip(), const []),
    );
    expect(csv.codeUnitAt(0), 0xFEFF); // BOM
    expect(csv,
        contains('Data;Categoria;Fornitore;Importo;Valuta;Importo EUR;Tasso;Note'));
  });

  test('formats date, comma decimals, empty cells for nulls', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 1289.5,
        valuta: 'JPY',
        importoEur: 8.4,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('02/07/2026;Pranzo;;1289,50;JPY;8,40;;'));
  });

  test('quotes a note containing the separator', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.cena,
        importo: 10,
        valuta: 'EUR',
        note: 'cena; con cliente',
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('"cena; con cliente"'));
  });

  test('total row omits the note when nothing is unconverted', () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        importoEur: 10,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    // Total is the last row: CsvEncoder adds no trailing eol after it.
    expect(csv, contains('TOTALE EUR;;;;;10,00'));
  });

  test('per-currency summary reports count, total and what is unconverted',
      () {
    final csv = const CsvExportService().build(TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 1000,
        valuta: 'JPY',
        importoEur: null,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]));
    expect(csv, contains('RIEPILOGO PER VALUTA'));
    // valuta;n. spese;totale;totale EUR;senza conversione
    expect(csv, contains('JPY;1;1000,00;0,00;1'));
    expect(csv, isNot(contains('esclude')));
  });
}
