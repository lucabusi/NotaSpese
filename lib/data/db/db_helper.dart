import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Opens nota_spese.db, enforces PRAGMA foreign_keys=ON on every
/// connection (Specifiche.md §5) and owns schema creation/versioning.
/// Production: DbHelper(). Tests: DbHelper(factory: databaseFactoryFfi,
/// path: inMemoryDatabasePath).
class DbHelper {
  DbHelper({this._factory, this._path});

  /// Bump on any schema change (formal migrations deferred to v1.1).
  static const int dbVersion = 1;
  static const String dbFileName = 'nota_spese.db';

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _db;

  Future<Database> get database async {
    final cached = _db;
    if (cached != null && cached.isOpen) return cached;
    final factory = _factory ?? databaseFactory;
    final path = _path ?? join(await factory.getDatabasesPath(), dbFileName);
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE trasferte (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  nome           TEXT NOT NULL,
  luogo          TEXT,
  data_inizio    TEXT NOT NULL,
  data_fine      TEXT,
  valuta_default TEXT NOT NULL DEFAULT 'EUR',
  lingua_default TEXT,
  archiviata     INTEGER NOT NULL DEFAULT 0,
  note           TEXT,
  created_at     TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE spese (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  trasferta_id INTEGER NOT NULL REFERENCES trasferte(id),
  data         TEXT NOT NULL,
  categoria    TEXT NOT NULL,
  fornitore    TEXT,
  importo      REAL NOT NULL,
  valuta       TEXT NOT NULL,
  importo_eur  REAL,
  tasso_cambio REAL,
  note         TEXT,
  ocr_engine   TEXT,
  created_at   TEXT NOT NULL
)''');
    await db.execute('CREATE INDEX idx_spese_trasferta ON spese(trasferta_id)');
    await db.execute('CREATE INDEX idx_spese_data ON spese(data)');
    await db.execute('''
CREATE TABLE foto (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  spesa_id   INTEGER NOT NULL UNIQUE REFERENCES spese(id),
  file_path  TEXT NOT NULL,
  thumb_path TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
  }
}
