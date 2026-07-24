import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip({String valuta = 'JPY'}) => Trasferta(
      id: 1,
      nome: 'Tokyo',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      dataFine: DateTime(2026, 7, 5),
      valutaDefault: valuta,
      createdAt: DateTime(2026, 7, 1),
    );

Spesa _spesa({
  int? id,
  DateTime? data,
  Categoria categoria = Categoria.pranzo,
  double importo = 1000,
  String valuta = 'JPY',
  double? importoEur,
  DateTime? createdAt,
}) =>
    Spesa(
      id: id,
      trasfertaId: 1,
      data: data ?? DateTime(2026, 7, 2),
      categoria: categoria,
      importo: importo,
      valuta: valuta,
      importoEur: importoEur,
      createdAt: createdAt ?? DateTime(2026, 7, 2, 12),
    );

void main() {
  test('righe sorted by data then createdAt', () {
    final r = TrasfertaReport.build(_trip(), [
      _spesa(id: 1, data: DateTime(2026, 7, 3), createdAt: DateTime(2026, 7, 3, 9)),
      _spesa(id: 2, data: DateTime(2026, 7, 2), createdAt: DateTime(2026, 7, 2, 15)),
      _spesa(id: 3, data: DateTime(2026, 7, 2), createdAt: DateTime(2026, 7, 2, 8)),
    ]);
    expect(r.righe.map((e) => e.spesaId).toList(), [3, 2, 1]);
  });

  test('totaliPerValuta puts trip currency first then descending amount', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(valuta: 'USD', importo: 50),
      _spesa(valuta: 'JPY', importo: 1000),
      _spesa(valuta: 'EUR', importo: 200),
    ]);
    expect(r.totaliPerValuta.keys.first, 'JPY');
    // EUR (200) before USD (50) among the non-trip currencies.
    expect(r.totaliPerValuta.keys.toList(), ['JPY', 'EUR', 'USD']);
  });

  test('totaleEur sums non-null, countSenzaEur counts nulls', () {
    final r = TrasfertaReport.build(_trip(), [
      _spesa(importoEur: 6.5),
      _spesa(importoEur: 3.5),
      _spesa(importoEur: null),
    ]);
    expect(r.totaleEur, closeTo(10.0, 1e-9));
    expect(r.countSenzaEur, 1);
  });

  test('single-currency trip: category totals in original currency', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(categoria: Categoria.pranzo, importo: 1000, valuta: 'JPY', importoEur: 6),
      _spesa(categoria: Categoria.pranzo, importo: 500, valuta: 'JPY', importoEur: 3),
      _spesa(categoria: Categoria.taxi, importo: 800, valuta: 'JPY', importoEur: 5),
    ]);
    expect(r.valutaCategorie, 'JPY');
    expect(r.totaliPerCategoria[Categoria.pranzo], 1500);
    expect(r.totaliPerCategoria[Categoria.taxi], 800);
  });

  test('multi-currency trip: category totals in EUR excluding non-converted', () {
    final r = TrasfertaReport.build(_trip(valuta: 'JPY'), [
      _spesa(categoria: Categoria.pranzo, importo: 1000, valuta: 'JPY', importoEur: 6),
      _spesa(categoria: Categoria.pranzo, importo: 10, valuta: 'USD', importoEur: null),
      _spesa(categoria: Categoria.taxi, importo: 20, valuta: 'USD', importoEur: 18),
    ]);
    expect(r.valutaCategorie, 'EUR');
    // The JPY pranzo (6 EUR) counts; the USD pranzo (no EUR) is excluded.
    expect(r.totaliPerCategoria[Categoria.pranzo], closeTo(6, 1e-9));
    expect(r.totaliPerCategoria[Categoria.taxi], closeTo(18, 1e-9));
  });
}
