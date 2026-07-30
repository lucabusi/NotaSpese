import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late FotoRepository fotoRepo;
  late PhotoService photoService;
  late Directory baseDir;
  late int trasfertaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    baseDir = await Directory.systemTemp.createTemp('detail_ctrl');
    dbHelper =
        DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    fotoRepo =
        FotoRepository(dbHelper, basePathProvider: () async => baseDir.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    photoService = PhotoService(SettingsService(),
        basePathProvider: () async => baseDir.path);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() async {
    await dbHelper.close();
    await baseDir.delete(recursive: true);
  });

  TrasfertaDetailController controller() => TrasfertaDetailController(
      trasfertaId, trasfertaRepo, spesaRepo, fotoRepo, photoService);

  Future<String> writeSourceImage() async {
    final im = img.Image(width: 640, height: 480);
    img.fill(im, color: img.ColorRgb8(10, 90, 160));
    final path = p.join(baseDir.path, 'src.jpg');
    await File(path).writeAsBytes(img.encodeJpg(im));
    return path;
  }

  Spesa spesaEur({int? id, double importo = 40}) => Spesa(
        id: id,
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 11),
        categoria: Categoria.cena,
        importo: importo,
        valuta: 'EUR',
        importoEur: importo,
        createdAt: DateTime(2026, 7, 11, 21),
      );

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
    expect(c.totaliPerCategoria, {Categoria.taxi: 20.0});
    expect(c.fotoBySpesa, isEmpty);
  });

  test('spese CRUD reloads grouped list and totals', () async {
    final c = controller();
    await c.load();

    await c.createSpesa(spesaEur());
    expect(c.speseByData, hasLength(1));
    expect(c.totaleEur, 40);
    expect(c.totaliPerCategoria, {Categoria.cena: 40.0});

    final salvata = c.speseByData.values.first.first;
    await c.updateSpesa(Spesa(
      id: salvata.id,
      trasfertaId: trasfertaId,
      data: salvata.data,
      categoria: Categoria.pranzo,
      importo: 25,
      valuta: 'EUR',
      importoEur: 25,
      createdAt: salvata.createdAt,
    ));
    expect(c.totaleEur, 25);
    expect(c.totaliPerCategoria, {Categoria.pranzo: 25.0});

    await c.deleteSpesa(salvata.id!);
    expect(c.speseByData, isEmpty);
    expect(c.totaleEur, 0);
    expect(c.totaliPerCategoria, isEmpty);
  });

  test('photo lifecycle: attach on create, replace, remove, delete spesa',
      () async {
    final c = controller();
    await c.load();
    final src = await writeSourceImage();

    // Attach on create.
    await c.createSpesa(spesaEur(), fotoSourcePath: src);
    final salvata = c.speseByData.values.first.first;
    final foto = c.fotoBySpesa[salvata.id];
    expect(foto, isNotNull);
    final file1 = File(p.join(baseDir.path, foto!.filePath));
    final thumb1 = File(p.join(baseDir.path, foto.thumbPath));
    expect(file1.existsSync(), isTrue);
    expect(thumb1.existsSync(), isTrue);

    // Replace: new photo removes the old files.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await c.updateSpesa(spesaEur(id: salvata.id), fotoSourcePath: src);
    final foto2 = c.fotoBySpesa[salvata.id]!;
    expect(foto2.filePath, isNot(foto.filePath));
    expect(file1.existsSync(), isFalse);
    expect(File(p.join(baseDir.path, foto2.filePath)).existsSync(), isTrue);

    // Remove.
    await c.updateSpesa(spesaEur(id: salvata.id), rimuoviFoto: true);
    expect(c.fotoBySpesa, isEmpty);
    expect(File(p.join(baseDir.path, foto2.filePath)).existsSync(), isFalse);

    // Delete spesa with photo removes files too.
    await c.updateSpesa(spesaEur(id: salvata.id), fotoSourcePath: src);
    final foto3 = c.fotoBySpesa[salvata.id]!;
    await c.deleteSpesa(salvata.id!);
    expect(File(p.join(baseDir.path, foto3.filePath)).existsSync(), isFalse);
    expect(
        File(p.join(baseDir.path, foto3.thumbPath)).existsSync(), isFalse);
  });

  test('fotoBytesBySpesa returns bytes keyed by spesa id', () async {
    final c = controller();
    await c.load();
    final source = await writeSourceImage();
    await c.createSpesa(
      Spesa(
        trasfertaId: trasfertaId,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        createdAt: DateTime(2026, 7, 2),
      ),
      fotoSourcePath: source,
    );
    final spesaId = c.fotoBySpesa.keys.single;

    final bytes = await c.fotoBytesBySpesa();

    expect(bytes.keys, contains(spesaId));
    expect(bytes[spesaId], isNotEmpty);
    c.dispose();
  });

  test('setArchiviata and elimina act on the trip', () async {
    final c = controller();
    await c.load();

    await c.setArchiviata(true);
    expect(c.trasferta!.archiviata, isTrue);

    await c.elimina();
    expect(await trasfertaRepo.getById(trasfertaId), isNull);
  });

  test('single currency: valutaUnica set, categorie in that currency',
      () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 20),
    ));

    final c = controller();
    await c.load();

    expect(c.valutaUnica, 'JPY');
    expect(c.valutaCategorie, 'JPY');
    expect(c.totaliPerCategoria, {Categoria.cena: 3000.0});
  });

  test('two currencies: valutaUnica null, categorie fall back to EUR',
      () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      importoEur: 18,
      createdAt: DateTime(2026, 7, 11, 20),
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

    expect(c.valutaUnica, isNull);
    expect(c.valutaCategorie, 'EUR');
    expect(c.totaliPerCategoria, {Categoria.cena: 18.0, Categoria.taxi: 20.0});
  });

  test('no spese: valutaUnica null and categorie empty', () async {
    final c = controller();
    await c.load();

    expect(c.valutaUnica, isNull);
    expect(c.totaliPerCategoria, isEmpty);
  });

  test('load fills the per-currency breakdown', () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      importoEur: 18,
      createdAt: DateTime(2026, 7, 11, 21),
    ));
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 12),
      categoria: Categoria.taxi,
      importo: 50,
      valuta: 'AED',
      createdAt: DateTime(2026, 7, 12, 9),
    ));

    final c = controller();
    await c.load();

    expect(c.breakdown.map((b) => b.valuta).toSet(), {'JPY', 'AED'});
    final aed = c.breakdown.firstWhere((b) => b.valuta == 'AED');
    expect(aed.count, 1);
    expect(aed.totale, 50);
    expect(aed.totaleEur, 0);
    expect(aed.countSenzaEur, 1);
  });

  test('ricalcolaConversioni without a backfill service is a no-op', () async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
    ));
    final c = controller();
    await c.load();

    final outcome = await c.ricalcolaConversioni();

    expect(outcome.convertite, 0);
    expect(outcome.fallite, 0);
    expect(c.countSenzaEur, 1, reason: 'nothing was converted');
  });
}
