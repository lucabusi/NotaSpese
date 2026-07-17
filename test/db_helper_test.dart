import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;

  setUp(() {
    dbHelper = DbHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => dbHelper.close());

  test('creates schema with the three tables and indexes', () async {
    final db = await dbHelper.database;
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = tables.map((r) => r['name']).toSet();
    expect(names.containsAll(['trasferte', 'spese', 'foto']), isTrue);

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'");
    final indexNames = indexes.map((r) => r['name']).toSet();
    expect(indexNames.containsAll(['idx_spese_trasferta', 'idx_spese_data']),
        isTrue);
  });

  test('foreign keys are ON for the connection', () async {
    final db = await dbHelper.database;
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first.values.first, 1);
  });

  test('rejects spesa referencing a missing trasferta', () async {
    final db = await dbHelper.database;
    expect(
      () => db.insert('spese', {
        'trasferta_id': 999,
        'data': '2026-07-17',
        'categoria': 'altro',
        'importo': 1.0,
        'valuta': 'EUR',
        'created_at': '2026-07-17T10:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('enforces UNIQUE(spesa_id) on foto (1:1)', () async {
    final db = await dbHelper.database;
    final tId = await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-17',
      'valuta_default': 'EUR',
      'archiviata': 0,
      'created_at': '2026-07-17T10:00:00.000',
    });
    final sId = await db.insert('spese', {
      'trasferta_id': tId,
      'data': '2026-07-17',
      'categoria': 'altro',
      'importo': 1.0,
      'valuta': 'EUR',
      'created_at': '2026-07-17T10:00:00.000',
    });
    Map<String, Object?> fotoRow() => {
          'spesa_id': sId,
          'file_path': 'receipts/x.jpg',
          'thumb_path': 'thumbnails/x.jpg',
          'created_at': '2026-07-17T10:00:00.000',
        };
    await db.insert('foto', fotoRow());
    expect(() => db.insert('foto', fotoRow()),
        throwsA(isA<DatabaseException>()));
  });

  test('database version is 1', () async {
    final db = await dbHelper.database;
    expect(await db.getVersion(), DbHelper.dbVersion);
    expect(DbHelper.dbVersion, 1);
  });
}
