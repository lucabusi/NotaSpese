import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db/db_helper.dart';

/// Local backup/restore of the whole dataset: one self-contained zip with
/// `nota_spese.db` at the root and every photo under `foto/`
/// (Specifiche.md §9). No manifest — the restore validates the extracted DB
/// schema instead.
///
/// UI-agnostic: paths, temp dir, clock, DB factory and the "close the current
/// connection" callback are injected, so the whole flow is host-testable and
/// no dialog/SnackBar lives here.
class BackupService {
  BackupService({
    required Future<String> Function() dbPathProvider,
    required Future<Directory> Function() photoDirProvider,
    required Future<void> Function() closeDatabase,
    Future<Directory> Function()? tempDirProvider,
    DatabaseFactory? dbFactory,
    DateTime Function()? now,
  })  : _dbPath = dbPathProvider,
        _photoDir = photoDirProvider,
        // ignore: prefer_initializing_formals
        _closeDatabase = closeDatabase,
        _tempDir = tempDirProvider ?? getTemporaryDirectory,
        // ignore: prefer_initializing_formals
        _dbFactory = dbFactory,
        _now = now ?? DateTime.now;

  final Future<String> Function() _dbPath;
  final Future<Directory> Function() _photoDir;
  // Consumed by restoreBackup (next task): closes the live DB connection
  // before the extracted file overwrites it.
  // ignore: unused_field
  final Future<void> Function() _closeDatabase;
  final Future<Directory> Function() _tempDir;
  // Consumed by restoreBackup (next task): lets tests open the restored DB
  // with an in-memory/ffi factory to validate its schema.
  // ignore: unused_field
  final DatabaseFactory? _dbFactory;
  final DateTime Function() _now;

  /// Zip entry prefix for photos. Written explicitly (never derived from the
  /// source dir name) so a backup is readable whatever the dir is called.
  static const String photoEntryDir = 'foto';

  static String backupFileName(DateTime now) =>
      'nota_spese_backup_${DateFormat('yyyyMMdd_HHmmss').format(now)}.zip';

  /// Zips DB + photos into a temp file and returns it. The caller decides the
  /// destination (share sheet).
  Future<File> createBackup() async {
    final zipFile =
        File(p.join((await _tempDir()).path, backupFileName(_now())));
    if (zipFile.existsSync()) await zipFile.delete();
    final encoder = ZipFileEncoder();
    var open = false;
    try {
      encoder.create(zipFile.path);
      open = true;
      final db = File(await _dbPath());
      if (db.existsSync()) await encoder.addFile(db, DbHelper.dbFileName);
      final photos = await _photoDir();
      if (photos.existsSync()) {
        for (final entity in photos.listSync(recursive: true)) {
          if (entity is! File) continue;
          final relative =
              p.split(p.relative(entity.path, from: photos.path)).join('/');
          await encoder.addFile(entity, '$photoEntryDir/$relative');
        }
      }
      await encoder.close();
      return zipFile;
    } catch (_) {
      // Never leave a partial zip behind (spec: cleanup on exception).
      if (open) {
        try {
          await encoder.close();
        } catch (_) {
          // [NON-BLOCKING] the encoder is being discarded anyway.
        }
      }
      if (zipFile.existsSync()) await zipFile.delete();
      rethrow;
    }
  }

  /// v1.1 (Google Drive): interface placeholder, never called by the UI.
  Future<void> uploadToDrive() =>
      throw UnimplementedError('Backup su Google Drive: v1.1');
}
