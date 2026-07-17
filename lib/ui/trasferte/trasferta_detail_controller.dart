import 'package:flutter/foundation.dart';

import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';

/// Detail screen state: the trip, its spese grouped by date and totals.
class TrasfertaDetailController extends ChangeNotifier {
  TrasfertaDetailController(
      this.trasfertaId, this._trasfertaRepository, this._spesaRepository);

  final int trasfertaId;
  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;

  bool loading = false;
  Trasferta? trasferta;
  Map<DateTime, List<Spesa>> speseByData = {};
  double totaleEur = 0;
  int countSenzaEur = 0;
  Map<String, double> totaliPerValuta = {};

  Future<void> load() async {
    loading = true;
    notifyListeners();
    trasferta = await _trasfertaRepository.getById(trasfertaId);
    speseByData =
        await _spesaRepository.getByTrasfertaGroupedByData(trasfertaId);
    totaleEur = await _spesaRepository.totaleEur(trasfertaId);
    countSenzaEur = await _spesaRepository.countSenzaEur(trasfertaId);
    totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);
    loading = false;
    notifyListeners();
  }

  Future<void> updateTrasferta(Trasferta aggiornata) async {
    await _trasfertaRepository.update(aggiornata);
    await load();
  }

  Future<void> setArchiviata(bool archiviata) async {
    await _trasfertaRepository.setArchiviata(trasfertaId, archiviata);
    await load();
  }

  Future<void> elimina() => _trasfertaRepository.delete(trasfertaId);
}
