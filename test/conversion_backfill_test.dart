import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/services/currency/conversion_backfill_service.dart';
import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late SpesaRepository repo;
  late int trasfertaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = SpesaRepository(
        dbHelper, FotoRepository(dbHelper, basePathProvider: () async => '.'));
    final db = await dbHelper.database;
    trasfertaId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-15',
      'valuta_default': 'JPY',
      'archiviata': 0,
      'created_at': '2026-07-15T08:00:00.000',
    });
  });

  tearDown(() => dbHelper.close());

  Spesa spesa({
    double importo = 1000,
    String valuta = 'JPY',
    double? importoEur,
  }) =>
      Spesa(
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 15),
        categoria: Categoria.altro,
        importo: importo,
        valuta: valuta,
        importoEur: importoEur,
        createdAt: DateTime(2026, 7, 15, 10),
      );

  ConversionBackfillService serviceWith(MockClient client) =>
      ConversionBackfillService(
          repo, ExchangeService(SettingsService(), client: client));

  MockClient rateClient(double rate) =>
      MockClient((request) async => http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'JPY',
            'date': '2026-07-15',
            'rates': {'EUR': rate},
          }),
          200,
          headers: {'content-type': 'application/json'}));

  test('converts only the rows missing importo_eur', () async {
    final giaConvertita = await repo.insert(spesa(importoEur: 99));
    final daConvertire = await repo.insert(spesa(importo: 2000));

    final outcome = await serviceWith(rateClient(0.0061)).run(trasfertaId);

    expect(outcome.convertite, 1);
    expect(outcome.fallite, 0);
    expect((await repo.getById(giaConvertita))!.importoEur, 99,
        reason: 'an already converted spesa must not be touched');
    final aggiornata = await repo.getById(daConvertire);
    expect(aggiornata!.importoEur, closeTo(12.2, 0.0001));
    expect(aggiornata.tassoCambio, 0.0061);
  });

  test('a failed conversion leaves the row NULL and is counted', () async {
    await repo.insert(spesa());
    final client = MockClient((request) async => http.Response('down', 500));

    final outcome = await serviceWith(client).run(trasfertaId);

    expect(outcome.convertite, 0);
    expect(outcome.fallite, 1);
    expect(outcome.nessunaConversione, isTrue);
    final righe = await repo.getByTrasferta(trasfertaId);
    expect(righe.single.importoEur, isNull);
  });

  test('nothing to do yields a zeroed outcome without network', () async {
    await repo.insert(spesa(importoEur: 5));
    final client = MockClient((request) async {
      fail('no conversion should be attempted');
    });

    final outcome = await serviceWith(client).run(trasfertaId);

    expect(outcome.convertite, 0);
    expect(outcome.fallite, 0);
  });

  test('other fields of a converted spesa survive the update', () async {
    final id = await repo.insert(spesa(importo: 2000));
    await serviceWith(rateClient(0.0061)).run(trasfertaId);
    final aggiornata = await repo.getById(id);
    expect(aggiornata!.importo, 2000);
    expect(aggiornata.valuta, 'JPY');
    expect(aggiornata.categoria, Categoria.altro);
    expect(aggiornata.trasfertaId, trasfertaId);
  });
}
