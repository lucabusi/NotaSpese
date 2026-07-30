import '../../core/constants/categories.dart';
import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../data/models/valuta_breakdown.dart';

/// One expense as it appears in an export (a flattened [Spesa]).
class ReportRow {
  const ReportRow({
    required this.spesaId,
    required this.data,
    required this.categoria,
    this.fornitore,
    required this.importo,
    required this.valuta,
    this.importoEur,
    this.tassoCambio,
    this.note,
  });

  final int? spesaId;
  final DateTime data;
  final Categoria categoria;
  final String? fornitore;
  final double importo;
  final String valuta;
  final double? importoEur;
  final double? tassoCambio;
  final String? note;
}

/// Pure aggregation of a trip's expenses for CSV/PDF export. Mirrors the
/// aggregation rules of [SpesaRepository] (per-currency totals, EUR total,
/// per-category totals) so an export matches the in-app screens exactly.
class TrasfertaReport {
  const TrasfertaReport({
    required this.trasferta,
    required this.righe,
    required this.breakdown,
    required this.totaliPerValuta,
    required this.totaleEur,
    required this.countSenzaEur,
    required this.totaliPerCategoria,
    required this.valutaCategorie,
  });

  final Trasferta trasferta;
  final List<ReportRow> righe;

  /// Per-currency detail: count + original total + converted total, ordered
  /// with the trip currency first. What the cover and the CSV summary show.
  final List<ValutaBreakdown> breakdown;

  /// Sum of `importo` per currency; trip currency first, then descending.
  final Map<String, double> totaliPerValuta;
  final double totaleEur;
  final int countSenzaEur;
  final Map<Categoria, double> totaliPerCategoria;

  /// Currency [totaliPerCategoria] is expressed in: the trip's single
  /// currency, or 'EUR' when the trip mixes currencies.
  final String valutaCategorie;

  static TrasfertaReport build(Trasferta trasferta, List<Spesa> spese) {
    final speseOrdinate = [...spese]..sort((a, b) {
        final byData = a.data.compareTo(b.data);
        return byData != 0 ? byData : a.createdAt.compareTo(b.createdAt);
      });

    final perValuta = <String, double>{};
    for (final s in spese) {
      perValuta[s.valuta] = (perValuta[s.valuta] ?? 0) + s.importo;
    }
    final valutaTrasferta = trasferta.valutaDefault;
    final breakdown = ordinaPerValuta([
      for (final valuta in perValuta.keys)
        ValutaBreakdown(
          valuta: valuta,
          count: spese.where((s) => s.valuta == valuta).length,
          totale: perValuta[valuta]!,
          totaleEur: spese
              .where((s) => s.valuta == valuta && s.importoEur != null)
              .fold<double>(0, (sum, s) => sum + s.importoEur!),
          countSenzaEur: spese
              .where((s) => s.valuta == valuta && s.importoEur == null)
              .length,
        ),
    ], valutaTrasferta);
    final totaliPerValuta = {for (final b in breakdown) b.valuta: b.totale};

    final totaleEur = spese
        .where((s) => s.importoEur != null)
        .fold<double>(0, (sum, s) => sum + s.importoEur!);
    final countSenzaEur = spese.where((s) => s.importoEur == null).length;

    final valutaUnica =
        perValuta.length == 1 ? perValuta.keys.first : null;
    final valutaCategorie = valutaUnica ?? 'EUR';
    final totaliPerCategoria = <Categoria, double>{};
    for (final s in spese) {
      if (valutaUnica == null) {
        // Multi-currency: sum EUR, silently excluding non-converted spese
        // (same rule as SpesaRepository.totaliEurPerCategoria).
        if (s.importoEur == null) continue;
        totaliPerCategoria[s.categoria] =
            (totaliPerCategoria[s.categoria] ?? 0) + s.importoEur!;
      } else {
        totaliPerCategoria[s.categoria] =
            (totaliPerCategoria[s.categoria] ?? 0) + s.importo;
      }
    }

    return TrasfertaReport(
      trasferta: trasferta,
      righe: [
        for (final s in speseOrdinate)
          ReportRow(
            spesaId: s.id,
            data: s.data,
            categoria: s.categoria,
            fornitore: s.fornitore,
            importo: s.importo,
            valuta: s.valuta,
            importoEur: s.importoEur,
            tassoCambio: s.tassoCambio,
            note: s.note,
          ),
      ],
      breakdown: breakdown,
      totaliPerValuta: totaliPerValuta,
      totaleEur: totaleEur,
      countSenzaEur: countSenzaEur,
      totaliPerCategoria: totaliPerCategoria,
      valutaCategorie: valutaCategorie,
    );
  }
}
