import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Expense categories (spec: Specifiche.md §Modello Dati).
/// Stored in DB as TEXT via [name]; read back with Categoria.values.byName.
enum Categoria {
  pranzo('Pranzo', Symbols.lunch_dining),
  cena('Cena', Symbols.dinner_dining),
  colazione('Colazione', Symbols.bakery_dining),
  trasporto('Trasporto', Symbols.commute),
  taxi('Taxi', Symbols.local_taxi),
  hotel('Hotel', Symbols.hotel),
  parcheggio('Parcheggio', Symbols.local_parking),
  carburante('Carburante', Symbols.local_gas_station),
  telefono('Telefono', Symbols.call),
  altro('Altro', Symbols.category);

  const Categoria(this.label, this.icon);

  /// UI label (Italian, per project convention).
  final String label;
  final IconData icon;
}
