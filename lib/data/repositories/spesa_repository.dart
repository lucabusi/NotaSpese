import '../../core/constants/categories.dart';
import '../db/db_helper.dart';
import '../models/spesa.dart';
import 'foto_repository.dart';

/// Expense CRUD + per-trasferta aggregations. Deleting a spesa also
/// removes its photo: files first, then both records in one transaction.
class SpesaRepository {
  SpesaRepository(this._dbHelper, this._fotoRepository);

  final DbHelper _dbHelper;
  final FotoRepository _fotoRepository;

  Future<int> insert(Spesa spesa) async {
    final db = await _dbHelper.database;
    return db.insert('spese', spesa.toMap());
  }

  Future<void> update(Spesa spesa) async {
    final db = await _dbHelper.database;
    await db.update('spese', spesa.toMap(),
        where: 'id = ?', whereArgs: [spesa.id]);
  }

  Future<Spesa?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('spese', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Spesa.fromMap(rows.first);
  }

  /// Photo files first, then foto + spesa records in one transaction.
  Future<void> delete(int id) async {
    final foto = await _fotoRepository.getBySpesa(id);
    if (foto != null) await _fotoRepository.deleteFiles([foto]);
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('foto', where: 'spesa_id = ?', whereArgs: [id]);
      await txn.delete('spese', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Spesa>> getByTrasferta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('spese',
        where: 'trasferta_id = ?',
        whereArgs: [trasfertaId],
        orderBy: 'data DESC, id DESC');
    return rows.map(Spesa.fromMap).toList();
  }

  /// Keys ordered by date DESC (insertion order of the LinkedHashMap).
  Future<Map<DateTime, List<Spesa>>> getByTrasfertaGroupedByData(
      int trasfertaId) async {
    final spese = await getByTrasferta(trasfertaId);
    // Map literal is a LinkedHashMap: keys keep the DESC insertion order.
    final grouped = <DateTime, List<Spesa>>{};
    for (final spesa in spese) {
      grouped.putIfAbsent(spesa.data, () => []).add(spesa);
    }
    return grouped;
  }

  /// Sum of `importo` in original currency, grouped by `valuta`.
  Future<Map<String, double>> totaliPerValuta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT valuta, SUM(importo) AS totale FROM spese '
        'WHERE trasferta_id = ? GROUP BY valuta',
        [trasfertaId]);
    return {
      for (final row in rows)
        row['valuta'] as String: (row['totale'] as num).toDouble(),
    };
  }

  /// Sum of converted amounts; spese without importo_eur are excluded
  /// (callers surface them via [countSenzaEur]).
  Future<double> totaleEur(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT SUM(importo_eur) AS totale FROM spese WHERE trasferta_id = ?',
        [trasfertaId]);
    return (rows.first['totale'] as num?)?.toDouble() ?? 0;
  }

  Future<int> countByTrasferta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM spese WHERE trasferta_id = ?',
        [trasfertaId]);
    return rows.first['n'] as int;
  }

  Future<int> countSenzaEur(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM spese '
        'WHERE trasferta_id = ? AND importo_eur IS NULL',
        [trasfertaId]);
    return rows.first['n'] as int;
  }

  Future<Map<Categoria, double>> totaliEurPerCategoria(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT categoria, SUM(importo_eur) AS totale FROM spese '
        'WHERE trasferta_id = ? AND importo_eur IS NOT NULL '
        'GROUP BY categoria',
        [trasfertaId]);
    return _perCategoria(rows);
  }

  /// Sum of `importo` (original currency) grouped by categoria. Meaningful
  /// only when the trasferta has a single valuta — callers check
  /// [totaliPerValuta] first and fall back to [totaliEurPerCategoria].
  Future<Map<Categoria, double>> totaliPerCategoria(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT categoria, SUM(importo) AS totale FROM spese '
        'WHERE trasferta_id = ? GROUP BY categoria',
        [trasfertaId]);
    return _perCategoria(rows);
  }

  /// Rows of `categoria` + `totale` into a per-category map.
  Map<Categoria, double> _perCategoria(List<Map<String, Object?>> rows) => {
    for (final row in rows)
      Categoria.values.byName(row['categoria'] as String):
          (row['totale'] as num).toDouble(),
  };
}
