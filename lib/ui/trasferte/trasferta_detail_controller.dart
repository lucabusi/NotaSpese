import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/categories.dart';
import '../../data/models/foto.dart';
import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../data/models/valuta_breakdown.dart';
import '../../data/repositories/foto_repository.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../services/currency/conversion_backfill_service.dart';
import '../../services/photo/photo_service.dart';

/// Detail screen state: the trip, its spese grouped by date, totals and
/// per-spesa photos. Photo attach/replace/remove goes through here so the
/// UI never touches PhotoService/FotoRepository ordering rules.
class TrasfertaDetailController extends ChangeNotifier {
  TrasfertaDetailController(this.trasfertaId, this._trasfertaRepository,
      this._spesaRepository, this._fotoRepository, this._photoService,
      {this.backfill});

  final int trasfertaId;
  final TrasfertaRepository _trasfertaRepository;
  final SpesaRepository _spesaRepository;
  final FotoRepository _fotoRepository;
  final PhotoService _photoService;

  /// Optional so tests and previews can build a controller without wiring
  /// the network; [ricalcolaConversioni] degrades to a no-op without it.
  final ConversionBackfillService? backfill;

  bool loading = false;
  Trasferta? trasferta;
  Map<DateTime, List<Spesa>> speseByData = {};
  double totaleEur = 0;
  int countSenzaEur = 0;
  Map<String, double> totaliPerValuta = {};
  List<ValutaBreakdown> breakdown = [];
  Map<Categoria, double> totaliPerCategoria = {};
  Map<int, Foto> fotoBySpesa = {};

  /// Absolute thumbnail paths, resolved at load time so tiles never build
  /// a new Future per frame (FutureBuilder rebuild-loop gotcha).
  Map<int, String> thumbAbsBySpesa = {};

  /// The trip's only currency, or null when spese mix currencies (or there
  /// are none): totals in different currencies must never be summed.
  String? get valutaUnica =>
      totaliPerValuta.length == 1 ? totaliPerValuta.keys.first : null;

  /// Currency the per-category totals are expressed in.
  String get valutaCategorie => valutaUnica ?? 'EUR';

  Future<void> load() async {
    loading = true;
    notifyListeners();
    trasferta = await _trasfertaRepository.getById(trasfertaId);
    speseByData =
        await _spesaRepository.getByTrasfertaGroupedByData(trasfertaId);
    totaleEur = await _spesaRepository.totaleEur(trasfertaId);
    countSenzaEur = await _spesaRepository.countSenzaEur(trasfertaId);
    totaliPerValuta = await _spesaRepository.totaliPerValuta(trasfertaId);
    breakdown = await _spesaRepository.breakdownPerValuta(trasfertaId,
        valutaTrasferta: trasferta?.valutaDefault ?? 'EUR');
    totaliPerCategoria = valutaUnica == null
        ? await _spesaRepository.totaliEurPerCategoria(trasfertaId)
        : await _spesaRepository.totaliPerCategoria(trasfertaId);
    final fotoList = await _fotoRepository.getByTrasferta(trasfertaId);
    fotoBySpesa = {for (final foto in fotoList) foto.spesaId: foto};
    thumbAbsBySpesa = {
      for (final foto in fotoList)
        foto.spesaId: await _photoService.absolutePath(foto.thumbPath),
    };
    loading = false;
    notifyListeners();
  }

  /// User-triggered backfill of the missing EUR conversions. Returns a
  /// zeroed outcome when no backfill service is wired (tests, previews).
  Future<BackfillOutcome> ricalcolaConversioni() async {
    final servizio = backfill;
    if (servizio == null) {
      return const BackfillOutcome(convertite: 0, fallite: 0);
    }
    final outcome = await servizio.run(trasfertaId);
    if (outcome.convertite > 0) await load();
    return outcome;
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

  /// Full-size receipt photo bytes keyed by spesa id, for PDF export.
  /// Best-effort: a spesa whose photo file is missing/unreadable is skipped.
  Future<Map<int, Uint8List>> fotoBytesBySpesa() async {
    final result = <int, Uint8List>{};
    for (final entry in fotoBySpesa.entries) {
      try {
        final abs = await _photoService.absolutePath(entry.value.filePath);
        result[entry.key] = await File(abs).readAsBytes();
      } catch (_) {
        // Skip: the PDF simply omits this receipt's photo page.
      }
    }
    return result;
  }

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
