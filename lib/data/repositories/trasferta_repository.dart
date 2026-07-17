import '../db/db_helper.dart';
import '../models/foto.dart';
import '../models/trasferta.dart';
import 'foto_repository.dart';

/// Trip CRUD + archive + explicit delete cascade (Specifiche.md §5):
/// photo files → foto records → spese → trasferta, records in one
/// SQLite transaction (files can't join it, so they go first).
class TrasfertaRepository {
  TrasfertaRepository(this._dbHelper, this._fotoRepository);

  final DbHelper _dbHelper;
  final FotoRepository _fotoRepository;

  Future<int> insert(Trasferta trasferta) async {
    final db = await _dbHelper.database;
    return db.insert('trasferte', trasferta.toMap());
  }

  Future<void> update(Trasferta trasferta) async {
    final db = await _dbHelper.database;
    await db.update('trasferte', trasferta.toMap(),
        where: 'id = ?', whereArgs: [trasferta.id]);
  }

  Future<Trasferta?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db
        .query('trasferte', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Trasferta.fromMap(rows.first);
  }

  Future<List<Trasferta>> getAttive() => _getByArchiviata(0);

  Future<List<Trasferta>> getArchiviate() => _getByArchiviata(1);

  Future<List<Trasferta>> _getByArchiviata(int archiviata) async {
    final db = await _dbHelper.database;
    final rows = await db.query('trasferte',
        where: 'archiviata = ?',
        whereArgs: [archiviata],
        orderBy: 'data_inizio DESC');
    return rows.map(Trasferta.fromMap).toList();
  }

  Future<void> setArchiviata(int id, bool archiviata) async {
    final db = await _dbHelper.database;
    await db.update('trasferte', {'archiviata': archiviata ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Explicit cascade; never relies on ON DELETE CASCADE (Specifiche.md §5).
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    final fotoRows = await db.rawQuery(
        'SELECT f.* FROM foto f '
        'JOIN spese s ON s.id = f.spesa_id '
        'WHERE s.trasferta_id = ?',
        [id]);
    await _fotoRepository.deleteFiles(fotoRows.map(Foto.fromMap).toList());
    await db.transaction((txn) async {
      await txn.delete('foto',
          where: 'spesa_id IN (SELECT id FROM spese WHERE trasferta_id = ?)',
          whereArgs: [id]);
      await txn.delete('spese', where: 'trasferta_id = ?', whereArgs: [id]);
      await txn.delete('trasferte', where: 'id = ?', whereArgs: [id]);
    });
  }
}
