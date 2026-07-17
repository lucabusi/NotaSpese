import 'package:flutter/foundation.dart';

import '../../data/models/trasferta.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';

/// Row data for the trip list: trip + per-trip aggregates.
class TrasfertaListItem {
  const TrasfertaListItem({
    required this.trasferta,
    required this.numSpese,
    required this.totaleEur,
  });

  final Trasferta trasferta;
  final int numSpese;
  final double totaleEur;
}

/// Backs both the "Trasferte attive" and "Archivio" tabs (flag [archiviate]).
/// Every mutation reloads from the repositories and notifies.
class TrasferteListController extends ChangeNotifier {
  TrasferteListController(this._trasfertaRepository, this._spesaRepository,
      {required this.archiviate});

  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;
  final bool archiviate;

  bool loading = false;
  List<TrasfertaListItem> items = [];
  double totaleComplessivoEur = 0;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final trasferte = archiviate
        ? await _trasfertaRepository.getArchiviate()
        : await _trasfertaRepository.getAttive();
    final list = <TrasfertaListItem>[];
    var totale = 0.0;
    for (final t in trasferte) {
      final numSpese = await _spesaRepository.countByTrasferta(t.id!);
      final totaleEur = await _spesaRepository.totaleEur(t.id!);
      list.add(TrasfertaListItem(
          trasferta: t, numSpese: numSpese, totaleEur: totaleEur));
      totale += totaleEur;
    }
    items = list;
    totaleComplessivoEur = totale;
    loading = false;
    notifyListeners();
  }

  Future<void> create(Trasferta trasferta) async {
    await _trasfertaRepository.insert(trasferta);
    await load();
  }

  Future<void> updateTrasferta(Trasferta trasferta) async {
    await _trasfertaRepository.update(trasferta);
    await load();
  }

  Future<void> setArchiviata(int id, bool archiviata) async {
    await _trasfertaRepository.setArchiviata(id, archiviata);
    await load();
  }

  Future<void> elimina(int id) async {
    await _trasfertaRepository.delete(id);
    await load();
  }
}
