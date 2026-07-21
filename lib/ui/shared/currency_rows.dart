/// Per-currency rows for a trip's totals: the trip's own currency first,
/// then the others by descending amount. An empty map yields a single zero
/// row in the trip currency, so a trip without spese still shows an amount.
List<MapEntry<String, double>> righeValuta(
    Map<String, double> totali, String valutaTrasferta) {
  if (totali.isEmpty) return [MapEntry(valutaTrasferta, 0)];
  return totali.entries.toList()
    ..sort((a, b) {
      if (a.key == valutaTrasferta) return -1;
      if (b.key == valutaTrasferta) return 1;
      return b.value.compareTo(a.value);
    });
}

/// Whether the "≈ € x" EUR hint should render: there is something actually
/// converted, and it is not already the only currency shown as the primary
/// total (a single-EUR trip would otherwise show a redundant "≈ € x" under
/// its own "€ x").
bool mostraSuggerimentoEur(
        double totaleEur, Map<String, double> totaliPerValuta) =>
    totaleEur > 0 &&
    !(totaliPerValuta.length == 1 && totaliPerValuta.containsKey('EUR'));
