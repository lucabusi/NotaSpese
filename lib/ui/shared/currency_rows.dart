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
