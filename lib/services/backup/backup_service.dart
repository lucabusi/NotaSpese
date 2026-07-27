import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db/db_helper.dart';

/// Outcome of a restore. [error] is a ready-to-show Italian message; the
/// caller owns the dialog/SnackBar.
class RestoreResult {
  const RestoreResult.success() : error = null;
  const RestoreResult.failure(this.error);

  final String? error;

  bool get ok => error == null;
}

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
  // Closes the live DB connection before the extracted file overwrites it.
  final Future<void> Function() _closeDatabase;
  final Future<Directory> Function() _tempDir;
  // Lets tests open the restored DB with an in-memory/ffi factory to
  // validate its schema.
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
      try {
        if (zipFile.existsSync()) await zipFile.delete();
      } catch (_) {
        // [NON-BLOCKING] best-effort cleanup: the original failure below is
        // the one the caller needs, not a secondary delete error.
      }
      rethrow;
    }
  }

  /// Extracts [zip], refuses anything that isn't a nota_spese DB, and only
  /// then swaps the live DB + photo dir. Current data survives every failure
  /// path: the previous files are parked as `.bak` / `_bak` (or the first free
  /// name after those) and restored if the swap breaks halfway. On success the
  /// DB connection is closed and the caller shows the "riavvia l'app" dialog.
  /// Total by contract: every failure comes back as a [RestoreResult], none is
  /// thrown at the caller.
  Future<RestoreResult> restoreBackup(File zip) async {
    Directory? tempRoot;
    try {
      final tempParent = await _tempDir();
      if (!tempParent.existsSync()) await tempParent.create(recursive: true);
      // createTemp, not a timestamp: the clock is injectable (and coarse), so
      // a name derived from it would collide between two restores in the same
      // millisecond — and a leftover extraction would be read as this one's.
      tempRoot = await tempParent.createTemp('restore_');

      // Streaming, never readAsBytes: a backup with a few hundred photos is
      // hundreds of MB and must not be held in RAM on a phone.
      final InputFileStream input;
      try {
        input = InputFileStream(zip.path);
      } catch (_) {
        return const RestoreResult.failure(
            'Archivio non leggibile: zip corrotto o non valido.');
      }
      try {
        // ZipDecoder tolerates garbage input: with no "end of central
        // directory" signature found it just returns an empty archive instead
        // of throwing, so extractFileToDisk would silently produce nothing.
        // Check the decoder actually located that signature before trusting
        // the result — that's the real "is this a zip at all" signal.
        final decoder = ZipDecoder();
        final archive = decoder.decodeStream(input);
        if (decoder.directory.filePosition < 0) {
          throw const FormatException('no end-of-central-directory found');
        }
        await extractArchiveToDisk(archive, tempRoot.path);
      } catch (_) {
        return const RestoreResult.failure(
            'Archivio non leggibile: zip corrotto o non valido.');
      } finally {
        // The archive entries read lazily from [input] (they share its file
        // handle), so it can only be closed once the extraction is done.
        await input.close();
      }

      final extractedDb = File(p.join(tempRoot.path, DbHelper.dbFileName));
      if (!extractedDb.existsSync()) {
        return const RestoreResult.failure(
            'Backup incompleto: nota_spese.db mancante nello zip.');
      }
      if (!await _hasExpectedSchema(extractedDb.path)) {
        return const RestoreResult.failure(
            'Il backup non contiene un database valido.');
      }

      // Must be awaited (not just returned) so the finally below cannot
      // delete tempRoot — and the still-in-flight extracted DB inside it —
      // before the swap has actually finished moving the files out.
      final result = await _swapIn(
          extractedDb, Directory(p.join(tempRoot.path, photoEntryDir)));
      return result;
    } catch (_) {
      // restoreBackup is total: the caller's whole contract is RestoreResult,
      // so an unexpected failure (temp dir not creatable, DB factory refusing
      // to open, the close-connection callback blowing up) must come back as
      // a failure, never as a thrown exception.
      return const RestoreResult.failure(
          'Ripristino non riuscito: errore imprevisto.');
    } finally {
      final leftovers = tempRoot;
      try {
        if (leftovers != null && leftovers.existsSync()) {
          await leftovers.delete(recursive: true);
        }
      } catch (_) {
        // [NON-BLOCKING] temp leftovers cost space, nothing else; the OS
        // clears the cache dir eventually. Must not throw: a finally that
        // throws would escape past the catch above.
      }
    }
  }

  /// Opens the extracted DB read-only and checks the expected tables. Any
  /// exception (not a SQLite file, truncated, locked) means "invalid".
  Future<bool> _hasExpectedSchema(String path) async {
    final factory = _dbFactory ?? databaseFactory;
    Database? db;
    try {
      db = await factory.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final rows = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
      final names = rows.map((r) => r['name'] as String).toSet();
      return names.containsAll(DbHelper.expectedTables);
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// Assumes the sqflite default journal mode (DELETE): `nota_spese.db` is a
  /// single self-contained file with no `-wal`/`-shm` sidecars, so parking and
  /// moving that one file is a complete swap. If the app ever switches to WAL,
  /// the OLD sidecars would survive next to the NEW database and corrupt it —
  /// they must then be parked, moved and rolled back here as well.
  Future<RestoreResult> _swapIn(File newDb, Directory newPhotos) async {
    final dbPath = await _dbPath();
    final photoDir = await _photoDir();
    // Never reuse a name that is already taken: a `.bak`/`_bak` left by an
    // earlier failed restore is the only hand-recoverable copy of that data
    // (see _rollback), so this attempt parks alongside it (`.bak2`, `_bak2`, …)
    // instead of overwriting it.
    final dbBak = File(_freeName('$dbPath.bak'));
    final photoBak = Directory(_freeName('${photoDir.path}_bak'));

    await _closeDatabase();

    try {
      final currentDb = File(dbPath);
      if (currentDb.existsSync()) await currentDb.rename(dbBak.path);
      if (photoDir.existsSync()) await photoDir.rename(photoBak.path);

      await Directory(p.dirname(dbPath)).create(recursive: true);
      await _moveFile(newDb, dbPath);
      if (newPhotos.existsSync()) {
        await _moveDirectory(newPhotos, photoDir.path);
      } else {
        await photoDir.create(recursive: true);
      }
    } catch (_) {
      await _rollback(
        dbPath: dbPath,
        dbBak: dbBak,
        photoDir: photoDir,
        photoBak: photoBak,
      );
      return const RestoreResult.failure(
          'Ripristino non completato: i dati precedenti sono stati mantenuti.');
    }

    // The new data is in place: the swap has SUCCEEDED and dropping the parked
    // copies is plain cleanup. A failure here (file lock, permissions) must
    // never trigger a rollback — that would delete the freshly restored data.
    // A leftover .bak/_bak only costs disk space.
    await _deleteQuietly(dbBak);
    await _deleteQuietly(photoBak);
    return const RestoreResult.success();
  }

  /// Rolls back whatever the swap actually managed to do. Driven by the state
  /// on disk, not by how far the caller thinks it got, so a swap that broke
  /// halfway is recovered correctly. Best effort: never throws — if a step
  /// fails the .bak copies stay on disk and the data is recoverable by hand
  /// instead of silently lost.
  Future<void> _rollback({
    required String dbPath,
    required File dbBak,
    required Directory photoDir,
    required Directory photoBak,
  }) async {
    if (dbBak.existsSync()) {
      try {
        final halfDb = File(dbPath);
        if (halfDb.existsSync()) await halfDb.delete();
        await dbBak.rename(dbPath);
      } catch (_) {
        // [NON-BLOCKING] see the doc comment: the .bak stays put.
      }
    }
    if (photoBak.existsSync()) {
      try {
        if (photoDir.existsSync()) await photoDir.delete(recursive: true);
        await photoBak.rename(photoDir.path);
      } catch (_) {
        // [NON-BLOCKING] see the doc comment: the _bak stays put.
      }
    }
  }

  /// First unused name in the `base`, `base2`, `base3`, … series.
  String _freeName(String base) {
    var candidate = base;
    var suffix = 2;
    while (FileSystemEntity.typeSync(candidate) !=
        FileSystemEntityType.notFound) {
      candidate = '$base${suffix++}';
    }
    return candidate;
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } catch (_) {
      // [NON-BLOCKING] cleanup only — see the call site.
    }
  }

  /// rename() fails across volumes (photos can live on external storage while
  /// the extraction happens in the cache dir) — fall back to copy + delete.
  Future<void> _moveFile(File source, String targetPath) async {
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      await source.copy(targetPath);
      await source.delete();
    }
  }

  Future<void> _moveDirectory(Directory source, String targetPath) async {
    try {
      await source.rename(targetPath);
      return;
    } on FileSystemException {
      // Cross-volume: copy the tree, then drop the source.
    }
    await Directory(targetPath).create(recursive: true);
    for (final entity in source.listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: source.path);
      if (entity is Directory) {
        await Directory(p.join(targetPath, relative)).create(recursive: true);
      } else if (entity is File) {
        final target = File(p.join(targetPath, relative));
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
    await source.delete(recursive: true);
  }

  /// v1.1 (Google Drive): interface placeholder, never called by the UI.
  Future<void> uploadToDrive() =>
      throw UnimplementedError('Backup su Google Drive: v1.1');
}
