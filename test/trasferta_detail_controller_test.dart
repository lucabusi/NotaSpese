import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late int trasfertaId;

  setUp(() async {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() => dbHelper.close());

  TrasfertaDetailController controller() =>
      TrasfertaDetailController(trasfertaId, trasfertaRepo, spesaRepo);

  test('load exposes trip, grouped spese and totals', () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 12),
      categoria: Categoria.taxi,
      importo: 20,
      valuta: 'EUR',
      importoEur: 20,
      createdAt: DateTime(2026, 7, 12, 9),
    ));

    final c = controller();
    await c.load();

    expect(c.trasferta!.nome, 'Tokyo');
    expect(c.speseByData.keys.toList(),
        [DateTime(2026, 7, 12), DateTime(2026, 7, 11)]);
    expect(c.totaleEur, 20);
    expect(c.countSenzaEur, 1);
    expect(c.totaliPerValuta, {'JPY': 3000.0, 'EUR': 20.0});
  });

  test('setArchiviata and elimina act on the trip', () async {
    final c = controller();
    await c.load();

    await c.setArchiviata(true);
    expect(c.trasferta!.archiviata, isTrue);

    await c.elimina();
    expect(await trasfertaRepo.getById(trasfertaId), isNull);
  });
}
