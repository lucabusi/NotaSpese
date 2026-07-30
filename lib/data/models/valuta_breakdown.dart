/// Per-currency slice of a trip: how many expenses were made in a currency,
/// how much they add up to in that currency, how much of that is converted
/// to EUR, and how many are still missing a conversion.
///
/// Not a DB entity: an aggregation of [Spesa] rows, shared by the detail
/// screen and the CSV/PDF exports so both show the same numbers.
class ValutaBreakdown {
  const ValutaBreakdown({
    required this.valuta,
    required this.count,
    required this.totale,
    required this.totaleEur,
    required this.countSenzaEur,
  });

  /// ISO 4217 code, raw as stored in `spese.valuta`.
  final String valuta;
  final int count;

  /// Sum of `importo`, in [valuta].
  final double totale;

  /// Sum of `importo_eur`; 0 when nothing in this currency is converted.
  final double totaleEur;

  /// Expenses in this currency still without `importo_eur`.
  final int countSenzaEur;
}

/// Trip currency first, then descending by original-currency total. Returns a
/// new list; the input is left untouched.
///
/// Same rule as `righeValuta` in `ui/shared/currency_rows.dart`, which still
/// serves the trip list's `Map<String, double>` totals.
List<ValutaBreakdown> ordinaPerValuta(
        List<ValutaBreakdown> righe, String valutaTrasferta) =>
    [...righe]..sort((a, b) {
        if (a.valuta == valutaTrasferta) return -1;
        if (b.valuta == valutaTrasferta) return 1;
        return b.totale.compareTo(a.totale);
      });
