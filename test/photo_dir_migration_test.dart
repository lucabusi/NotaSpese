import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/photo/photo_dir_migration.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = PhotoDirMigrationService();

  late Directory root;
  late Directory from;
  late Directory to;

  setUp(() {
    root = Directory.systemTemp.createTempSync('migration_test_');
    from = Directory(p.join(root.path, 'old'))..createSync(recursive: true);
    to = Directory(p.join(root.path, 'new'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  void seed() {
    File(p.join(from.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
    File(p.join(from.path, 'IMG_2.jpg')).writeAsStringSync('photo-2');
    Directory(p.join(from.path, 'thumbnails')).createSync(recursive: true);
    File(p.join(from.path, 'thumbnails', 'IMG_1_thumb.jpg'))
        .writeAsStringSync('thumb-1');
  }

  test('missing source dir is a no-op success', () async {
    final result = await service
        .migrate(from: Directory(p.join(root.path, 'ghost')), to: to);

    expect(result.ok, isTrue);
    expect(result.movedFiles, 0);
  });

  test('moves every file keeping the relative structure', () async {
    seed();

    final result = await service.migrate(from: from, to: to);

    expect(result.ok, isTrue);
    expect(result.movedFiles, 3);
    expect(File(p.join(to.path, 'IMG_1.jpg')).readAsStringSync(), 'photo-1');
    expect(File(p.join(to.path, 'IMG_2.jpg')).readAsStringSync(), 'photo-2');
    expect(
        File(p.join(to.path, 'thumbnails', 'IMG_1_thumb.jpg'))
            .readAsStringSync(),
        'thumb-1');
    // Sources are gone: the relative DB paths now resolve under `to`.
    expect(from.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('a failing copy aborts: no copies left, sources untouched', () async {
    seed();
    // A directory where a file must be written makes File.copy throw.
    Directory(p.join(to.path, 'IMG_2.jpg')).createSync(recursive: true);

    final result = await service.migrate(from: from, to: to);

    expect(result.ok, isFalse);
    expect(result.error, contains('cartella precedente'));
    expect(
        from
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toSet(),
        {'IMG_1.jpg', 'IMG_2.jpg', 'IMG_1_thumb.jpg'});
    expect(to.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test(
      'a failing copy aborts: no leftover directories under an existing destination',
      () async {
    seed();
    // A file that sorts after `thumbnails` so it is copied last: every
    // directory the migration will create (`thumbnails`) is already in
    // place by the time this one fails, regardless of the exact iteration
    // order `listSync` happens to return.
    File(p.join(from.path, 'zzz_blocked.jpg')).writeAsStringSync('blocked');
    // Destination already exists (unrelated to the migration) and holds a
    // directory precisely where this last file must be copied, which is
    // what forces File.copy to throw.
    Directory(p.join(to.path, 'zzz_blocked.jpg')).createSync(recursive: true);

    final result = await service.migrate(from: from, to: to);

    expect(result.ok, isFalse);
    // The destination must be left exactly as found: `to` itself and the
    // pre-existing `zzz_blocked.jpg` directory survive, but no directory
    // created by the migration (e.g. `thumbnails`) is left behind.
    expect(to.existsSync(), isTrue);
    expect(Directory(p.join(to.path, 'zzz_blocked.jpg')).existsSync(), isTrue);
    expect(Directory(p.join(to.path, 'thumbnails')).existsSync(), isFalse);
    expect(
        to.listSync(recursive: true).map((e) => p.basename(e.path)).toSet(),
        {'zzz_blocked.jpg'});
  });

  test('a destination created by the migration is fully removed on abort',
      () async {
    seed();
    // Sorts after `thumbnails`, so whatever order `listSync` returns, this
    // file's copy is attempted only after `thumbnails` has already been
    // created — exercising cleanup of both `to` and `to/thumbnails`.
    File(p.join(from.path, 'zzz_blocked.jpg')).writeAsStringSync('blocked');
    expect(to.existsSync(), isFalse);

    // Calling an async function runs it synchronously up to its first
    // `await` — inside migrate() that is the very first
    // `target.parent.create()` call, before any `File.copy` has run for any
    // source. Deleting a source file right here (before this test awaits
    // the future) guarantees that file's later copy attempt throws
    // PathNotFoundException, without pre-creating anything under `to` the
    // way the other abort tests do (their blocking directory is created
    // *inside* `to`, which implicitly creates `to` itself before migrate()
    // even runs).
    final future = service.migrate(from: from, to: to);
    File(p.join(from.path, 'zzz_blocked.jpg')).deleteSync();
    final result = await future;

    expect(result.ok, isFalse);
    // `to` did not exist before the migration and must not exist after an
    // abort, even though the migration necessarily created it (and
    // `to/thumbnails`) while copying.
    expect(to.existsSync(), isFalse);
    // The other sources were never touched by the migration (the
    // post-copy delete phase never runs after an abort).
    expect(File(p.join(from.path, 'IMG_1.jpg')).existsSync(), isTrue);
    expect(File(p.join(from.path, 'IMG_2.jpg')).existsSync(), isTrue);
    expect(
        File(p.join(from.path, 'thumbnails', 'IMG_1_thumb.jpg')).existsSync(),
        isTrue);
  });

  test('a pre-existing empty destination survives the abort', () async {
    seed();
    File(p.join(from.path, 'zzz_blocked.jpg')).writeAsStringSync('blocked');
    to.createSync(recursive: true);

    final future = service.migrate(from: from, to: to);
    File(p.join(from.path, 'zzz_blocked.jpg')).deleteSync();
    final result = await future;

    expect(result.ok, isFalse);
    // `to` pre-existed (empty) and must survive, but end up empty again:
    // nothing the migration created inside it (`thumbnails`) or copied into
    // it is left behind.
    expect(to.existsSync(), isTrue);
    expect(to.listSync(recursive: true), isEmpty);
  });
}
