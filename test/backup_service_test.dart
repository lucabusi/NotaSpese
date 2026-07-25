import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/services/backup/backup_service.dart';
import 'package:path/path.dart' as p;

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
}
