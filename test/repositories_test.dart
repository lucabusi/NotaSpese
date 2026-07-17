import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/foto.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late Directory tempDir;

  setUp(() {
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('nota_spese_test');
  });

  tearDown(() async {
    await dbHelper.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Inserts a minimal trasferta + spesa, returns the spesa id.
  Future<int> insertSpesaFixture() async {
    final db = await dbHelper.database;
    final tId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-17',
      'valuta_default': 'EUR',
      'archiviata': 0,
      'created_at': '2026-07-17T10:00:00.000',
    });
    return db.insert('spese', {
      'trasferta_id': tId,
      'data': '2026-07-17',
      'categoria': 'altro',
      'importo': 1.0,
      'valuta': 'EUR',
      'created_at': '2026-07-17T10:00:00.000',
    });
  }

  /// Creates fake photo + thumbnail files under tempDir, returns the Foto.
  Foto createFotoFixture(int spesaId) {
    final rel = 'receipts/$spesaId.jpg';
    final thumbRel = 'thumbnails/$spesaId.jpg';
    File(p.join(tempDir.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync('jpg');
    File(p.join(tempDir.path, thumbRel))
      ..createSync(recursive: true)
      ..writeAsStringSync('thumb');
    return Foto(
      spesaId: spesaId,
      filePath: rel,
      thumbPath: thumbRel,
      createdAt: DateTime(2026, 7, 17, 10),
    );
  }

  group('FotoRepository', () {
    late FotoRepository repo;

    setUp(() {
      repo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
    });

    test('insert + getBySpesa round-trip', () async {
      final spesaId = await insertSpesaFixture();
      final id = await repo.insert(createFotoFixture(spesaId));
      expect(id, isPositive);
      final loaded = await repo.getBySpesa(spesaId);
      expect(loaded, isNotNull);
      expect(loaded!.filePath, 'receipts/$spesaId.jpg');
    });

    test('getBySpesa returns null when no photo', () async {
      final spesaId = await insertSpesaFixture();
      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa removes physical files AND record', () async {
      final spesaId = await insertSpesaFixture();
      final foto = createFotoFixture(spesaId);
      await repo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));
      final thumb = File(p.join(tempDir.path, foto.thumbPath));
      expect(file.existsSync(), isTrue);

      await repo.deleteBySpesa(spesaId);

      expect(file.existsSync(), isFalse);
      expect(thumb.existsSync(), isFalse);
      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa tolerates already-missing files', () async {
      final spesaId = await insertSpesaFixture();
      final foto = createFotoFixture(spesaId);
      await repo.insert(foto);
      File(p.join(tempDir.path, foto.filePath)).deleteSync();

      await repo.deleteBySpesa(spesaId); // must not throw

      expect(await repo.getBySpesa(spesaId), isNull);
    });

    test('deleteBySpesa with no photo is a no-op', () async {
      final spesaId = await insertSpesaFixture();
      await repo.deleteBySpesa(spesaId); // must not throw
    });
  });

  group('SpesaRepository', () {
    late FotoRepository fotoRepo;
    late SpesaRepository repo;
    late int trasfertaId;

    Spesa spesa({
      DateTime? data,
      Categoria categoria = Categoria.altro,
      double importo = 10,
      String valuta = 'EUR',
      double? importoEur,
    }) =>
        Spesa(
          trasfertaId: trasfertaId,
          data: data ?? DateTime(2026, 7, 17),
          categoria: categoria,
          importo: importo,
          valuta: valuta,
          importoEur: importoEur,
          createdAt: DateTime(2026, 7, 17, 10),
        );

    setUp(() async {
      fotoRepo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
      repo = SpesaRepository(dbHelper, fotoRepo);
      final db = await dbHelper.database;
      trasfertaId = await db.insert('trasferte', {
        'nome': 'T',
        'data_inizio': '2026-07-15',
        'valuta_default': 'EUR',
        'archiviata': 0,
        'created_at': '2026-07-15T08:00:00.000',
      });
    });

    test('insert + getById round-trip', () async {
      final id = await repo.insert(spesa(importo: 42.5, valuta: 'JPY'));
      final loaded = await repo.getById(id);
      expect(loaded!.importo, 42.5);
      expect(loaded.valuta, 'JPY');
      expect(loaded.trasfertaId, trasfertaId);
    });

    test('update persists changes', () async {
      final id = await repo.insert(spesa());
      final loaded = await repo.getById(id);
      await repo.update(Spesa(
        id: id,
        trasfertaId: loaded!.trasfertaId,
        data: loaded.data,
        categoria: Categoria.hotel,
        importo: 99,
        valuta: 'EUR',
        createdAt: loaded.createdAt,
      ));
      final updated = await repo.getById(id);
      expect(updated!.categoria, Categoria.hotel);
      expect(updated.importo, 99);
    });

    test('delete removes spesa, its foto record and files', () async {
      final id = await repo.insert(spesa());
      final foto = createFotoFixture(id);
      await fotoRepo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));

      await repo.delete(id);

      expect(await repo.getById(id), isNull);
      expect(await fotoRepo.getBySpesa(id), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('getByTrasfertaGroupedByData groups by date, newest first', () async {
      await repo.insert(spesa(data: DateTime(2026, 7, 15)));
      await repo.insert(spesa(data: DateTime(2026, 7, 16)));
      await repo.insert(spesa(data: DateTime(2026, 7, 16)));

      final grouped = await repo.getByTrasfertaGroupedByData(trasfertaId);

      expect(grouped.keys.toList(),
          [DateTime(2026, 7, 16), DateTime(2026, 7, 15)]);
      expect(grouped[DateTime(2026, 7, 16)]!.length, 2);
    });

    test('totaliPerValuta sums importo grouped by currency', () async {
      await repo.insert(spesa(importo: 10, valuta: 'EUR'));
      await repo.insert(spesa(importo: 5.5, valuta: 'EUR'));
      await repo.insert(spesa(importo: 3000, valuta: 'JPY'));

      final totali = await repo.totaliPerValuta(trasfertaId);

      expect(totali, {'EUR': 15.5, 'JPY': 3000.0});
    });

    test('totaleEur sums only converted spese, countSenzaEur the rest',
        () async {
      await repo.insert(spesa(importoEur: 10));
      await repo.insert(spesa(importoEur: 20.5));
      await repo.insert(spesa(valuta: 'JPY')); // not converted

      expect(await repo.totaleEur(trasfertaId), 30.5);
      expect(await repo.countSenzaEur(trasfertaId), 1);
    });

    test('countByTrasferta counts only that trip', () async {
      await repo.insert(spesa());
      await repo.insert(spesa());
      expect(await repo.countByTrasferta(trasfertaId), 2);
      expect(await repo.countByTrasferta(trasfertaId + 999), 0);
    });

    test('totaleEur is 0 for empty trasferta', () async {
      expect(await repo.totaleEur(trasfertaId), 0);
    });

    test('totaliEurPerCategoria groups by category, skips unconverted',
        () async {
      await repo.insert(spesa(categoria: Categoria.cena, importoEur: 25));
      await repo.insert(spesa(categoria: Categoria.cena, importoEur: 15));
      await repo.insert(spesa(categoria: Categoria.taxi, importoEur: 12));
      await repo.insert(spesa(categoria: Categoria.taxi)); // no EUR

      final totali = await repo.totaliEurPerCategoria(trasfertaId);

      expect(totali, {Categoria.cena: 40.0, Categoria.taxi: 12.0});
    });
  });

  group('TrasfertaRepository', () {
    late FotoRepository fotoRepo;
    late TrasfertaRepository repo;

    Trasferta trasferta({
      String nome = 'Trip',
      DateTime? dataInizio,
      bool archiviata = false,
    }) =>
        Trasferta(
          nome: nome,
          dataInizio: dataInizio ?? DateTime(2026, 7, 15),
          archiviata: archiviata,
          createdAt: DateTime(2026, 7, 15, 8),
        );

    setUp(() {
      fotoRepo = FotoRepository(dbHelper,
          basePathProvider: () async => tempDir.path);
      repo = TrasfertaRepository(dbHelper, fotoRepo);
    });

    test('insert + getById round-trip with defaults', () async {
      final id = await repo.insert(trasferta(nome: 'Tokyo'));
      final loaded = await repo.getById(id);
      expect(loaded!.nome, 'Tokyo');
      expect(loaded.valutaDefault, 'EUR');
      expect(loaded.archiviata, isFalse);
    });

    test('update persists changes', () async {
      final id = await repo.insert(trasferta());
      final loaded = await repo.getById(id);
      await repo.update(Trasferta(
        id: id,
        nome: 'Renamed',
        dataInizio: loaded!.dataInizio,
        valutaDefault: 'JPY',
        createdAt: loaded.createdAt,
      ));
      final updated = await repo.getById(id);
      expect(updated!.nome, 'Renamed');
      expect(updated.valutaDefault, 'JPY');
    });

    test('getAttive/getArchiviate filter and order by data_inizio DESC',
        () async {
      await repo.insert(
          trasferta(nome: 'Old', dataInizio: DateTime(2026, 5, 1)));
      await repo.insert(
          trasferta(nome: 'New', dataInizio: DateTime(2026, 7, 1)));
      await repo.insert(trasferta(nome: 'Archived', archiviata: true));

      final attive = await repo.getAttive();
      expect(attive.map((t) => t.nome).toList(), ['New', 'Old']);

      final archiviate = await repo.getArchiviate();
      expect(archiviate.map((t) => t.nome).toList(), ['Archived']);
    });

    test('setArchiviata archives and restores', () async {
      final id = await repo.insert(trasferta());
      await repo.setArchiviata(id, true);
      expect((await repo.getById(id))!.archiviata, isTrue);
      await repo.setArchiviata(id, false);
      expect((await repo.getById(id))!.archiviata, isFalse);
    });

    test('delete cascades: photo files, foto, spese, trasferta', () async {
      final id = await repo.insert(trasferta());
      final db = await dbHelper.database;
      final spesaId = await db.insert('spese', {
        'trasferta_id': id,
        'data': '2026-07-16',
        'categoria': 'cena',
        'importo': 30.0,
        'valuta': 'EUR',
        'created_at': '2026-07-16T21:00:00.000',
      });
      final foto = createFotoFixture(spesaId);
      await fotoRepo.insert(foto);
      final file = File(p.join(tempDir.path, foto.filePath));
      final thumb = File(p.join(tempDir.path, foto.thumbPath));

      await repo.delete(id);

      expect(await repo.getById(id), isNull);
      expect(await db.query('spese'), isEmpty);
      expect(await db.query('foto'), isEmpty);
      expect(file.existsSync(), isFalse);
      expect(thumb.existsSync(), isFalse);
    });

    test('delete of trasferta without spese works', () async {
      final id = await repo.insert(trasferta());
      await repo.delete(id);
      expect(await repo.getById(id), isNull);
    });
  });
}
