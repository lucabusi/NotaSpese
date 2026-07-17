import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/db_helper.dart';
import '../models/foto.dart';

/// Photo records + physical files. Deletion order is files FIRST,
/// then DB record (Specifiche.md §2): a dangling file is recoverable,
/// a dangling record pointing to nothing is a bug.
class FotoRepository {
  FotoRepository(this._dbHelper, {required this.basePathProvider});

  final DbHelper _dbHelper;

  /// Absolute photo directory; DB paths are relative to it.
  /// Wired to the configured photo dir in fase 4; tests inject a temp dir.
  final Future<String> Function() basePathProvider;

  Future<int> insert(Foto foto) async {
    final db = await _dbHelper.database;
    return db.insert('foto', foto.toMap());
  }

  /// All photos of a trip's spese (for the detail-list thumbnails).
  Future<List<Foto>> getByTrasferta(int trasfertaId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
        'SELECT foto.* FROM foto '
        'JOIN spese ON spese.id = foto.spesa_id '
        'WHERE spese.trasferta_id = ?',
        [trasfertaId]);
    return rows.map(Foto.fromMap).toList();
  }

  Future<Foto?> getBySpesa(int spesaId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('foto',
        where: 'spesa_id = ?', whereArgs: [spesaId], limit: 1);
    return rows.isEmpty ? null : Foto.fromMap(rows.first);
  }

  /// Deletes physical files first, then the record.
  Future<void> deleteBySpesa(int spesaId) async {
    final foto = await getBySpesa(spesaId);
    if (foto == null) return;
    await deleteFiles([foto]);
    final db = await _dbHelper.database;
    await db.delete('foto', where: 'spesa_id = ?', whereArgs: [spesaId]);
  }

  /// Deletes photo + thumbnail files only (records untouched).
  /// Missing or locked files are ignored: deletion must never block on
  /// them — an orphan file is recoverable, a half-deleted spesa is not.
  Future<void> deleteFiles(List<Foto> fotos) async {
    final base = await basePathProvider();
    for (final foto in fotos) {
      for (final rel in [foto.filePath, foto.thumbPath]) {
        final file = File(p.join(base, rel));
        try {
          if (file.existsSync()) await file.delete();
        } on FileSystemException {
          // [NON-BLOCKING] e.g. Windows file lock while an Image widget
          // still holds the handle (host tests); never seen on Android.
        }
      }
    }
  }
}
