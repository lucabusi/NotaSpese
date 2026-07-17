import 'package:flutter/foundation.dart';

import '../../core/constants/categories.dart';
import '../../data/models/foto.dart';
import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../data/repositories/foto_repository.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../services/photo/photo_service.dart';

/// Detail screen state: the trip, its spese grouped by date, totals and
/// per-spesa photos. Photo attach/replace/remove goes through here so the
/// UI never touches PhotoService/FotoRepository ordering rules.
class TrasfertaDetailController extends ChangeNotifier {
  TrasfertaDetailController(this.trasfertaId, this._trasfertaRepository,
      this._spesaRepository, this._fotoRepository, this._photoService);

  final int trasfertaId;
  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;
  final FotoRepository _fotoRepository;
  final PhotoService _photoService;

  bool loading = false;
  Trasferta? trasferta;
  Map<DateTime, List<Spesa>> speseByData = {};
  double totaleEur = 0;
  int countSenzaEur = 0;
  Map<String, double> totaliPerValuta = {};
  Map<Categoria, double> totaliEurPerCategoria = {};
  Map<int, Foto> fotoBySpesa = {};

  /// Absolute thumbnail paths, resolved at load time so tiles never build
  /// a new Future per frame (FutureBuilder rebuild-loop gotcha).
  Map<int, String> thumbAbsBySpesa = {};

  Future<void> load() async {
    loading = true;
    notifyListeners();
    trasferta = await _trasfertaRepository.getById(trasfertaId);
    speseByData =
        await _spesaRepository.getByTrasfertaGroupedByData(trasfertaId);
    totaleEur = await _spesaRepository.totaleEur(trasfertaId);
    countSenzaEur = await _spesaRepository.countSenzaEur(trasfertaId);
    totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);
    totaliEurPerCategoria =
        await _spesaRepository.totaliEurPerCategoria(trasfertaId);
    final fotoList = await _fotoRepository.getByTrasferta(trasfertaId);
    fotoBySpesa = {for (final foto in fotoList) foto.spesaId: foto};
    thumbAbsBySpesa = {
      for (final foto in fotoList)
        foto.spesaId: await _photoService.absolutePath(foto.thumbPath),
    };
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

  Future<void> createSpesa(Spesa spesa, {String? fotoSourcePath}) async {
    final id = await _spesaRepository.insert(spesa);
    if (fotoSourcePath != null) await _attachFoto(id, fotoSourcePath);
    await load();
  }

  /// A new photo replaces the existing one (files first, repo rule).
  Future<void> updateSpesa(Spesa spesa,
      {String? fotoSourcePath, bool rimuoviFoto = false}) async {
    await _spesaRepository.update(spesa);
    if (rimuoviFoto || fotoSourcePath != null) {
      await _fotoRepository.deleteBySpesa(spesa.id!);
    }
    if (fotoSourcePath != null) await _attachFoto(spesa.id!, fotoSourcePath);
    await load();
  }

  /// For the form/viewer path resolver (PhotoService stays private).
  Future<String> absolutePhotoPath(String relative) =>
      _photoService.absolutePath(relative);

  Future<void> _attachFoto(int spesaId, String sourcePath) async {
    final paths = await _photoService.process(sourcePath);
    await _fotoRepository.insert(Foto(
      spesaId: spesaId,
      filePath: paths.filePath,
      thumbPath: paths.thumbPath,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> deleteSpesa(int id) async {
    await _spesaRepository.delete(id);
    await load();
  }

  Future<void> elimina() => _trasfertaRepository.delete(trasfertaId);
}
