import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/services/backup/backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late Directory photoDir;
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    root = Directory.systemTemp.createTempSync('backup_test_');
    photoDir = Directory(p.join(root.path, 'foto'))..createSync(recursive: true);
    tempDir = Directory(p.join(root.path, 'tmp'))..createSync(recursive: true);
    dbFile = File(p.join(root.path, 'db', DbHelper.dbFileName));
    dbFile.parent.createSync(recursive: true);
    dbFile.writeAsStringSync('fake-db-bytes');
  });

  tearDown(() => root.deleteSync(recursive: true));

  BackupService service({Directory? photos}) => BackupService(
        dbPathProvider: () async => dbFile.path,
        photoDirProvider: () async => photos ?? photoDir,
        closeDatabase: () async {},
        tempDirProvider: () async => tempDir,
        now: () => DateTime(2026, 7, 25, 14, 30, 5),
      );

  test('file name carries the timestamp', () {
    expect(BackupService.backupFileName(DateTime(2026, 7, 25, 14, 30, 5)),
        'nota_spese_backup_20260725_143005.zip');
  });

  test('zip contains the DB at the root and photos under foto/', () async {
    File(p.join(photoDir.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
    Directory(p.join(photoDir.path, 'thumbnails')).createSync(recursive: true);
    File(p.join(photoDir.path, 'thumbnails', 'IMG_1_thumb.jpg'))
        .writeAsStringSync('thumb-1');

    final zip = await service().createBackup();

    expect(p.basename(zip.path), 'nota_spese_backup_20260725_143005.zip');
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    expect(archive.files.map((f) => f.name).toSet(), {
      DbHelper.dbFileName,
      'foto/IMG_1.jpg',
      'foto/thumbnails/IMG_1_thumb.jpg',
    });
    expect(String.fromCharCodes(archive.findFile(DbHelper.dbFileName)!.content),
        'fake-db-bytes');
  });

  test('missing photo dir still produces a DB-only zip', () async {
    final zip = await service(photos: Directory(p.join(root.path, 'ghost')))
        .createBackup();

    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    expect(archive.files.map((f) => f.name), [DbHelper.dbFileName]);
  });

  test('failure leaves no partial zip behind', () async {
    final broken = BackupService(
      dbPathProvider: () async => throw const FileSystemException('boom'),
      photoDirProvider: () async => photoDir,
      closeDatabase: () async {},
      tempDirProvider: () async => tempDir,
      now: () => DateTime(2026, 7, 25, 14, 30, 5),
    );

    await expectLater(broken.createBackup(), throwsA(isA<FileSystemException>()));
    expect(tempDir.listSync(), isEmpty);
  });

  test('uploadToDrive is an unimplemented v1.1 stub', () {
    expect(service().uploadToDrive, throwsA(isA<UnimplementedError>()));
  });

  group('restoreBackup', () {
    setUpAll(sqfliteFfiInit);

    /// Builds a real nota_spese DB at [path] with one trip called [tripName].
    /// Deletes any placeholder file first: the setUp fixture writes plain
    /// text there, and SQLite refuses to open a non-database file.
    Future<void> writeValidDb(String path, String tripName) async {
      final existing = File(path);
      if (existing.existsSync()) existing.deleteSync();
      final helper =
          DbHelper(factory: databaseFactoryFfiNoIsolate, path: path);
      final db = await helper.database;
      await db.insert('trasferte', {
        'nome': tripName,
        'data_inizio': '2026-07-25',
        'valuta_default': 'EUR',
        'archiviata': 0,
        'created_at': '2026-07-25T10:00:00.000',
      });
      await helper.close();
    }

    /// Zips [dbPath] + [photos] the same way createBackup does.
    Future<File> zipOf({required String dbPath, Directory? photos}) async {
      final zip = File(p.join(root.path, 'source_backup.zip'));
      final encoder = ZipFileEncoder()..create(zip.path);
      await encoder.addFile(File(dbPath), DbHelper.dbFileName);
      if (photos != null) {
        for (final entity in photos.listSync(recursive: true)) {
          if (entity is! File) continue;
          final relative =
              p.split(p.relative(entity.path, from: photos.path)).join('/');
          await encoder.addFile(entity, 'foto/$relative');
        }
      }
      await encoder.close();
      return zip;
    }

    late BackupService restoreService;
    var closed = 0;

    setUp(() {
      closed = 0;
      restoreService = BackupService(
        dbPathProvider: () async => dbFile.path,
        photoDirProvider: () async => photoDir,
        closeDatabase: () async => closed++,
        tempDirProvider: () async => tempDir,
        dbFactory: databaseFactoryFfiNoIsolate,
        now: () => DateTime(2026, 7, 25, 14, 30, 5),
      );
    });

    test('valid zip replaces DB and photos, closes the connection', () async {
      // Current state: a DB with "Vecchia" and one stale photo.
      await writeValidDb(dbFile.path, 'Vecchia');
      File(p.join(photoDir.path, 'STALE.jpg')).writeAsStringSync('stale');
      // Backup content: a DB with "Nuova" and a different photo.
      final sourceDb = p.join(root.path, 'source', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final sourcePhotos = Directory(p.join(root.path, 'source_foto'))
        ..createSync(recursive: true);
      File(p.join(sourcePhotos.path, 'IMG_9.jpg')).writeAsStringSync('nine');
      final zip = await zipOf(dbPath: sourceDb, photos: sourcePhotos);

      final result = await restoreService.restoreBackup(zip);

      expect(result.ok, isTrue);
      expect(closed, 1);
      expect(File(p.join(photoDir.path, 'IMG_9.jpg')).readAsStringSync(),
          'nine');
      expect(File(p.join(photoDir.path, 'STALE.jpg')).existsSync(), isFalse);
      final helper = DbHelper(
          factory: databaseFactoryFfiNoIsolate, path: dbFile.path);
      final rows = await (await helper.database).query('trasferte');
      expect(rows.single['nome'], 'Nuova');
      await helper.close();
      // No leftovers.
      expect(File('${dbFile.path}.bak').existsSync(), isFalse);
      expect(Directory('${photoDir.path}_bak').existsSync(), isFalse);
    });

    test('zip whose DB lacks the expected tables is refused', () async {
      await writeValidDb(dbFile.path, 'Vecchia');
      final bogus = File(p.join(root.path, DbHelper.dbFileName));
      final helper = DbHelper(
          factory: databaseFactoryFfiNoIsolate, path: bogus.path);
      final db = await helper.database;
      await db.execute('DROP TABLE foto');
      await helper.close();
      final zip = await zipOf(dbPath: bogus.path);

      final result = await restoreService.restoreBackup(zip);

      expect(result.ok, isFalse);
      expect(result.error, contains('database valido'));
      final current = DbHelper(
          factory: databaseFactoryFfiNoIsolate, path: dbFile.path);
      final rows = await (await current.database).query('trasferte');
      expect(rows.single['nome'], 'Vecchia');
      await current.close();
    });

    test('corrupt zip is reported, current data intact', () async {
      await writeValidDb(dbFile.path, 'Vecchia');
      final corrupt = File(p.join(root.path, 'corrupt.zip'))
        ..writeAsStringSync('this is not a zip');

      final result = await restoreService.restoreBackup(corrupt);

      expect(result.ok, isFalse);
      expect(result.error, contains('corrotto'));
      expect(File(dbFile.path).existsSync(), isTrue);
    });

    test('zip without nota_spese.db is reported', () async {
      final zip = File(p.join(root.path, 'no_db.zip'));
      final encoder = ZipFileEncoder()..create(zip.path);
      final loose = File(p.join(root.path, 'readme.txt'))
        ..writeAsStringSync('nothing useful');
      await encoder.addFile(loose, 'readme.txt');
      await encoder.close();

      final result = await restoreService.restoreBackup(zip);

      expect(result.ok, isFalse);
      expect(result.error, contains('nota_spese.db'));
    });

    test('a failed swap rolls the previous DB back', () async {
      // A photo dir that can never be created: one of its path components is
      // a regular file, so _moveDirectory blows up *after* the DB has been
      // parked and the new one moved in — exactly the half-swap _rollback
      // exists for.
      final blocker = File(p.join(root.path, 'blocker.txt'))
        ..writeAsStringSync('not a directory');
      final unusablePhotos = Directory(p.join(blocker.path, 'foto'));
      final breaking = BackupService(
        dbPathProvider: () async => dbFile.path,
        photoDirProvider: () async => unusablePhotos,
        closeDatabase: () async => closed++,
        tempDirProvider: () async => tempDir,
        dbFactory: databaseFactoryFfiNoIsolate,
        now: () => DateTime(2026, 7, 25, 14, 30, 5),
      );
      await writeValidDb(dbFile.path, 'Vecchia');
      final sourceDb = p.join(root.path, 'source_rb', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final sourcePhotos = Directory(p.join(root.path, 'source_rb_foto'))
        ..createSync(recursive: true);
      File(p.join(sourcePhotos.path, 'IMG_7.jpg')).writeAsStringSync('seven');
      final zip = await zipOf(dbPath: sourceDb, photos: sourcePhotos);

      final result = await breaking.restoreBackup(zip);

      expect(result.ok, isFalse);
      expect(result.error, contains('dati precedenti'));
      // The previous DB is back where it belongs, not parked as .bak.
      expect(File('${dbFile.path}.bak').existsSync(), isFalse);
      final helper =
          DbHelper(factory: databaseFactoryFfiNoIsolate, path: dbFile.path);
      final rows = await (await helper.database).query('trasferte');
      expect(rows.single['nome'], 'Vecchia');
      await helper.close();
    });

    test('a failed swap rolls the photo dir back', () async {
      // Mirror image of the test above: here the DB path is the unusable one
      // (a regular file sits where a parent directory should be), so the photo
      // dir IS parked and the swap then dies on
      // Directory(dirname(dbPath)).create — the only way to reach the photo
      // half of _rollback, which is what protects the whole photo library.
      final blocker = File(p.join(root.path, 'blocker_db.txt'))
        ..writeAsStringSync('not a directory');
      final unusableDb = p.join(blocker.path, 'db', DbHelper.dbFileName);
      File(p.join(photoDir.path, 'KEEP.jpg')).writeAsStringSync('keep');
      final breaking = BackupService(
        dbPathProvider: () async => unusableDb,
        photoDirProvider: () async => photoDir,
        closeDatabase: () async => closed++,
        tempDirProvider: () async => tempDir,
        dbFactory: databaseFactoryFfiNoIsolate,
        now: () => DateTime(2026, 7, 25, 14, 30, 5),
      );
      final sourceDb = p.join(root.path, 'source_prb', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final sourcePhotos = Directory(p.join(root.path, 'source_prb_foto'))
        ..createSync(recursive: true);
      File(p.join(sourcePhotos.path, 'IMG_8.jpg')).writeAsStringSync('eight');
      final zip = await zipOf(dbPath: sourceDb, photos: sourcePhotos);

      final result = await breaking.restoreBackup(zip);

      expect(result.ok, isFalse);
      expect(result.error, contains('dati precedenti'));
      // The photo library is back at its own path, not parked as _bak, and the
      // backup's photos never made it in.
      expect(File(p.join(photoDir.path, 'KEEP.jpg')).readAsStringSync(),
          'keep');
      expect(File(p.join(photoDir.path, 'IMG_8.jpg')).existsSync(), isFalse);
      expect(Directory('${photoDir.path}_bak').existsSync(), isFalse);
      expect(File(unusableDb).existsSync(), isFalse);
    });

    test('a pre-existing .bak from an earlier failure is not destroyed',
        () async {
      await writeValidDb(dbFile.path, 'Vecchia');
      // Leftovers of a previous, failed restore: the only hand-recoverable
      // copy of the data. A second attempt must not wipe them.
      final oldBak = File('${dbFile.path}.bak')
        ..writeAsStringSync('previous-recovery-copy');
      final oldPhotoBak = Directory('${photoDir.path}_bak')
        ..createSync(recursive: true);
      File(p.join(oldPhotoBak.path, 'OLD.jpg')).writeAsStringSync('old');

      final sourceDb = p.join(root.path, 'source_keepbak', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final zip = await zipOf(dbPath: sourceDb);

      final result = await restoreService.restoreBackup(zip);

      expect(result.ok, isTrue);
      expect(oldBak.readAsStringSync(), 'previous-recovery-copy');
      expect(File(p.join(oldPhotoBak.path, 'OLD.jpg')).readAsStringSync(),
          'old');
      // The copies parked by *this* restore are cleaned up.
      expect(File('${dbFile.path}.bak2').existsSync(), isFalse);
      expect(Directory('${photoDir.path}_bak2').existsSync(), isFalse);
    });

    test('an unexpected failure comes back as a RestoreResult, not a throw',
        () async {
      final exploding = BackupService(
        dbPathProvider: () async => dbFile.path,
        photoDirProvider: () async => photoDir,
        closeDatabase: () async => throw StateError('cannot close'),
        tempDirProvider: () async => tempDir,
        dbFactory: databaseFactoryFfiNoIsolate,
        now: () => DateTime(2026, 7, 25, 14, 30, 5),
      );
      final sourceDb = p.join(root.path, 'source_boom', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final zip = await zipOf(dbPath: sourceDb);

      final result = await exploding.restoreBackup(zip);

      expect(result.ok, isFalse);
      expect(result.error, contains('Ripristino non riuscito'));
    });

    test('leftovers of a same-clock temp dir do not leak into the restore',
        () async {
      // The clock is fixed, so a millisecond-named temp dir is not unique:
      // a previous run's extraction must not be picked up as this one's.
      final stale = Directory(p.join(
          tempDir.path,
          'restore_'
          '${DateTime(2026, 7, 25, 14, 30, 5).millisecondsSinceEpoch}'));
      Directory(p.join(stale.path, 'foto')).createSync(recursive: true);
      File(p.join(stale.path, 'foto', 'GHOST.jpg')).writeAsStringSync('ghost');

      final sourceDb = p.join(root.path, 'source_clock', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final sourcePhotos = Directory(p.join(root.path, 'source_clock_foto'))
        ..createSync(recursive: true);
      File(p.join(sourcePhotos.path, 'IMG_3.jpg')).writeAsStringSync('three');
      final zip = await zipOf(dbPath: sourceDb, photos: sourcePhotos);

      final result = await restoreService.restoreBackup(zip);

      expect(result.ok, isTrue);
      expect(File(p.join(photoDir.path, 'IMG_3.jpg')).existsSync(), isTrue);
      expect(File(p.join(photoDir.path, 'GHOST.jpg')).existsSync(), isFalse);
    });

    test('a cleanup failure after a completed swap still reports success',
        () async {
      // Read-only attribute: renaming the current DB to .bak still works, but
      // deleting that .bak afterwards fails with access denied — a cleanup
      // error on an already-successful swap.
      await writeValidDb(dbFile.path, 'Vecchia');
      Process.runSync('attrib', ['+R', dbFile.path]);
      final sourceDb = p.join(root.path, 'source_ro', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final zip = await zipOf(dbPath: sourceDb);

      final result = await restoreService.restoreBackup(zip);

      final leftover = File('${dbFile.path}.bak');
      if (leftover.existsSync()) {
        Process.runSync('attrib', ['-R', leftover.path]);
      }
      expect(result.ok, isTrue);
      final helper =
          DbHelper(factory: databaseFactoryFfiNoIsolate, path: dbFile.path);
      final rows = await (await helper.database).query('trasferte');
      expect(rows.single['nome'], 'Nuova');
      await helper.close();
    },
        // Off Windows this regression is currently unprotected. The DB seam
        // used here has no POSIX equivalent (rename and unlink share the same
        // parent-directory write bit), but the photo half does: a chmod 0500
        // subdirectory inside the photo dir still renames with its parent
        // while the recursive delete of the _bak fails with EACCES (no-op as
        // root, so it would need its own skip). Not written here because it
        // cannot be run — let alone shown red then green — on this
        // Windows-only dev machine.
        skip: Platform.isWindows
            ? null
            : 'staged with the Windows read-only attribute: it blocks the '
                'cleanup delete without blocking the preceding rename');

    test('no temp extraction dir is left behind', () async {
      final sourceDb = p.join(root.path, 'source2', DbHelper.dbFileName);
      Directory(p.dirname(sourceDb)).createSync(recursive: true);
      await writeValidDb(sourceDb, 'Nuova');
      final zip = await zipOf(dbPath: sourceDb);

      await restoreService.restoreBackup(zip);

      expect(
          tempDir
              .listSync()
              .whereType<Directory>()
              .where((d) => p.basename(d.path).startsWith('restore_')),
          isEmpty);
    });
  });
}
