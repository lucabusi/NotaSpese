import '../../data/models/spesa.dart';
import '../../data/repositories/spesa_repository.dart';
import 'exchange_service.dart';

/// How a backfill run went, for the SnackBar the caller shows.
class BackfillOutcome {
  const BackfillOutcome({required this.convertite, required this.fallite});

  final int convertite;
  final int fallite;

  /// Nothing could be converted — usually offline, or a date outside the
  /// rate sources' history.
  bool get nessunaConversione => convertite == 0;
}

/// Fills in `importo_eur` for spese saved without a conversion (offline at
/// the time, or a currency no rate source covered back then). Triggered by
/// the user, never automatically: it costs network and writes to the DB.
///
/// Best-effort by construction: a spesa whose rate cannot be fetched is left
/// untouched and counted as failed, and the run always continues.
class ConversionBackfillService {
  const ConversionBackfillService(this._spese, this._exchange);

  final SpesaRepository _spese;
  final ExchangeService _exchange;

  Future<BackfillOutcome> run(int trasfertaId) async {
    final spese = await _spese.getByTrasferta(trasfertaId);
    var convertite = 0;
    var fallite = 0;
    for (final spesa in spese.where((s) => s.importoEur == null)) {
      final result = await _exchange.convert(
          amount: spesa.importo, from: spesa.valuta, date: spesa.data);
      if (result == null) {
        fallite++;
        continue;
      }
      await _spese.update(_conConversione(spesa, result));
      convertite++;
    }
    return BackfillOutcome(convertite: convertite, fallite: fallite);
  }

  /// Copy of [spesa] with the conversion filled in; every other field is
  /// carried over untouched (Spesa has no copyWith).
  Spesa _conConversione(Spesa spesa, ExchangeResult result) => Spesa(
        id: spesa.id,
        trasfertaId: spesa.trasfertaId,
        data: spesa.data,
        categoria: spesa.categoria,
        fornitore: spesa.fornitore,
        importo: spesa.importo,
        valuta: spesa.valuta,
        importoEur: result.amountEur,
        tassoCambio: result.rate,
        note: spesa.note,
        ocrEngine: spesa.ocrEngine,
        createdAt: spesa.createdAt,
      );
}
