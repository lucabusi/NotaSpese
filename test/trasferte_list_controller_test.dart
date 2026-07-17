import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferte_list_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late TrasferteListController controller;

  Trasferta trasferta({String nome = 'Trip', bool archiviata = false}) =>
      Trasferta(
        nome: nome,
        dataInizio: DateTime(2026, 7, 15),
        archiviata: archiviata,
        createdAt: DateTime(2026, 7, 15, 8),
      );

  setUp(() {
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    controller =
        TrasferteListController(trasfertaRepo, spesaRepo, archiviate: false);
  });

  tearDown(() => dbHelper.close());

  test('load exposes active trips with counts and totals', () async {
    final id = await trasfertaRepo.insert(trasferta(nome: 'Tokyo'));
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    await spesaRepo.insert(Spesa(
      trasfertaId: id,
      data: DateTime(2026, 7, 16),
      categoria: Categoria.cena,
      importo: 30,
      valuta: 'EUR',
      importoEur: 30,
      createdAt: DateTime(2026, 7, 16, 21),
    ));

    await controller.load();

    expect(controller.items.length, 1);
    expect(controller.items.first.trasferta.nome, 'Tokyo');
    expect(controller.items.first.numSpese, 1);
    expect(controller.items.first.totaleEur, 30);
    expect(controller.totaleComplessivoEur, 30);
  });

  test('archiviate: true lists only archived trips', () async {
    await trasfertaRepo.insert(trasferta(nome: 'Active'));
    await trasfertaRepo.insert(trasferta(nome: 'Old', archiviata: true));
    final archived =
        TrasferteListController(trasfertaRepo, spesaRepo, archiviate: true);

    await archived.load();

    expect(archived.items.map((i) => i.trasferta.nome).toList(), ['Old']);
  });

  test('create/updateTrasferta/setArchiviata/elimina reload the list',
      () async {
    await controller.create(trasferta(nome: 'A'));
    expect(controller.items.length, 1);

    final t = controller.items.first.trasferta;
    await controller.updateTrasferta(Trasferta(
      id: t.id,
      nome: 'B',
      dataInizio: t.dataInizio,
      createdAt: t.createdAt,
    ));
    expect(controller.items.first.trasferta.nome, 'B');

    await controller.setArchiviata(t.id!, true);
    expect(controller.items, isEmpty);

    await controller.setArchiviata(t.id!, false);
    await controller.elimina(t.id!);
    expect(controller.items, isEmpty);
    expect(await trasfertaRepo.getById(t.id!), isNull);
  });

  test('notifies listeners on load', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.load();
    expect(notified, greaterThanOrEqualTo(1));
  });
}
