# Fase 8 — Impostazioni + Backup/Restore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ImpostazioniMinimal` with a full settings screen (OCR, photo quality/dir/usage, exchange rates, backup, version) and add local backup/restore of DB + photos as a single zip.

**Architecture:** Three UI-agnostic services do the work — `BackupService` (zip create / validate+atomic swap restore / `uploadToDrive()` stub), `PhotoDirMigrationService` (copy-then-delete photo files with clean abort), `PhotoDirUsage` (file count + bytes). Each takes injected path providers and returns a result object; every dialog, `SnackBar` and progress indicator lives in `ImpostazioniScreen`. All services are pure `dart:io` + `sqflite`, so the whole feature is host-testable without an Android device.

**Tech Stack:** Dart/Flutter, `archive` (zip, new direct dep — already a transitive one), `file_selector` (zip picking, new), `share_plus` (already present, backup destination), `sqflite` + `sqflite_common_ffi` (schema validation and its tests), `shared_preferences`, `intl`.

Reference spec: `docs/superpowers/specs/2026-07-25-fase-8-impostazioni-backup-design.md`.

## Global Constraints

- Comments/code/commits in English; UI strings in Italian (project convention).
- Surgical changes only; match existing style. No unrequested refactoring.
- Commit at the end of each task. Never `--force`, `reset --hard`, or skip hooks.
- `flutter analyze` must stay at **zero issues**; `flutter test` must stay green.
- Version bump once, in Task 1: `pubspec.yaml` `0.11.0+16` and `lib/version.dart` `'0.11.0'` kept in sync.
- **Photo paths stored in the `foto` table are RELATIVE to the photo base dir** (`FotoRepository.basePathProvider`, `PhotoService.process` returns `IMG_<ts>.jpg` / `thumbnails/IMG_<ts>_thumb.jpg`). Consequences, binding for this plan:
  - Moving the photo files to a new base dir keeps every stored path valid → **the migration never touches the DB**.
  - Changing the photo dir *without* migrating would break every existing photo → the dialog offers only **"Migra ora" / "Annulla"** (spec decision 3 amended, user decision 2026-07-25). There is no "Lascia dove sono" option.
- **`file_selector: ^1.0.3` replaces `file_picker`** (spec/`Specifiche.md` amended, user decision 2026-07-25): `file_picker >=8.3.3 <12.0.0-beta.1` pins `win32 ^5.9.0` while `share_plus 13.2.1` needs `win32 ^6.0.1`, so the stable `file_picker` line resolves down to 3.0.4. `file_selector` is only used to **pick** the zip to restore; the backup destination is the **share sheet** (`SharePlus`), same flow as fase 7 export — `file_selector_android` has no save dialog.
- **`DbHelper.dbVersion` stays 1** (assumption, stated in the spec's "DB version" section as a bump): the schema does not change in fase 8, and raising the number without an `onUpgrade` handler makes `sqflite` throw on every existing install. The ToDo item "versione DB incrementabile" is satisfied by adding the no-op `onUpgrade` hook (Task 1) so a future bump cannot crash; `test/db_helper_test.dart` already asserts `dbVersion == 1`.
- Backup zip layout is fixed: `nota_spese.db` at the root + one `foto/<relative path>` entry per photo file (thumbnails included, `foto/thumbnails/...`). The prefix is written explicitly, never derived from the source dir's name.
- Restore never leaves the app half-migrated: validate the extracted DB **before** touching anything, then rename current DB/photo dir to `.bak` / `_bak`, move the new ones in, delete the baks only on success, roll back from the baks on any failure.
- New service code lives under `lib/services/backup/` and `lib/services/photo/`; the screen under `lib/ui/impostazioni/`; tests directly under `test/`.
- Emulator verification is an explicit **SKIP** (no emulator on this machine, `CLAUDE.md` gotcha); host unit/widget tests compensate, real verification is deferred to a physical-device run like fase 6b.

---

### Task 1: Dependencies, version bump, `DbHelper` path + upgrade hook

Foundation every later task consumes: the two new packages, the version bump, and the two `DbHelper` additions `BackupService` needs (DB file path, expected table names, no-op upgrade hook).

**Files:**
- Modify: `pubspec.yaml` (version line + `dependencies`)
- Modify: `lib/version.dart`
- Modify: `lib/data/db/db_helper.dart`
- Test: `test/db_helper_test.dart` (add two tests)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `DbHelper.databasePath() → Future<String>` — absolute path of `nota_spese.db`, resolved exactly like the `database` getter does (returns the injected `path` in tests).
  - `DbHelper.expectedTables → Set<String>` = `{'trasferte', 'spese', 'foto'}`.
  - `DbHelper.onUpgrade(Database db, int oldVersion, int newVersion) → Future<void>` — static no-op, wired into `OpenDatabaseOptions`.
  - Packages `archive` and `file_selector` available to import.

- [ ] **Step 1: Write the failing tests**

Append to `test/db_helper_test.dart`, before the closing `}` of `main()`:

```dart
  test('databasePath resolves to the injected path', () async {
    expect(await dbHelper.databasePath(), inMemoryDatabasePath);
  });

  test('expectedTables matches the tables actually created', () async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(names.containsAll(DbHelper.expectedTables), isTrue);
    expect(DbHelper.expectedTables, {'trasferte', 'spese', 'foto'});
  });

  test('onUpgrade is a no-op hook that leaves data untouched', () async {
    final db = await dbHelper.database;
    await db.insert('trasferte', {
      'nome': 'T',
      'data_inizio': '2026-07-25',
      'valuta_default': 'EUR',
      'archiviata': 0,
      'created_at': '2026-07-25T10:00:00.000',
    });

    await DbHelper.onUpgrade(db, 1, 2);

    expect((await db.query('trasferte')).length, 1);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/db_helper_test.dart`
Expected: FAIL — `The method 'databasePath' isn't defined for the class 'DbHelper'`, `expectedTables` / `onUpgrade` undefined (compile errors).

- [ ] **Step 3: Add the two packages**

Run: `flutter pub add archive:^4.0.9 file_selector:^1.0.3`
Expected: `Changed 2 dependencies!` and `pubspec.yaml` now lists both under `dependencies:` (keep them next to `pdf: ^3.13.0`; `archive` moves from transitive to direct).

- [ ] **Step 4: Bump the version**

In `pubspec.yaml` replace:

```yaml
version: 0.10.0+15
```

with:

```yaml
version: 0.11.0+16
```

Replace the whole body of `lib/version.dart`:

```dart
/// App version, shown in Settings and logs.
/// Bump on every functional change (keep in sync with pubspec.yaml).
const String appVersion = '0.11.0';
```

- [ ] **Step 5: Implement the `DbHelper` additions**

In `lib/data/db/db_helper.dart`, after the `dbFileName` constant, add:

```dart
  /// Tables a valid nota_spese DB must expose. Used by BackupService to
  /// validate a restored DB before it overwrites the current one.
  static const Set<String> expectedTables = {'trasferte', 'spese', 'foto'};
```

Replace the `database` getter's path line so both callers share one resolution:

```dart
  Future<Database> get database async {
    final cached = _db;
    if (cached != null && cached.isOpen) return cached;
    final factory = _factory ?? databaseFactory;
    final path = await databasePath();
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: onUpgrade,
      ),
    );
    _db = db;
    return db;
  }

  /// Absolute path of the DB file, resolved like [database] does.
  /// BackupService zips and swaps this file.
  Future<String> databasePath() async {
    final factory = _factory ?? databaseFactory;
    return _path ?? join(await factory.getDatabasesPath(), dbFileName);
  }

  /// No-op upgrade hook: v1.0 ships schema v1 with no formal migrations
  /// (Specifiche.md §7). It exists so a future [dbVersion] bump can't crash
  /// an existing install with "onUpgrade not implemented" — the per-version
  /// migration scripts arrive in v1.1.
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/db_helper_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 7: Verify analyze is clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/version.dart lib/data/db/db_helper.dart test/db_helper_test.dart
git commit -m "feat: archive/file_selector deps, DB path accessor and no-op upgrade hook"
```

---

### Task 2: `PhotoDirUsage` — photo folder size indicator

Pure filesystem measurement for the Settings "spazio usato" row (ToDo asks for file count + MB).

**Files:**
- Create: `lib/services/photo/photo_dir_usage.dart`
- Test: `test/photo_dir_usage_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class PhotoDirUsage { const PhotoDirUsage({required int fileCount, required int bytes}); final int fileCount; final int bytes; String get label; static PhotoDirUsage get empty; static Future<PhotoDirUsage> measure(Directory dir); }` — `label` is `'<n> file · <x,y> MB'` with one decimal.

- [ ] **Step 1: Write the failing test**

Create `test/photo_dir_usage_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/photo/photo_dir_usage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('usage_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('missing directory measures as empty', () async {
    final usage =
        await PhotoDirUsage.measure(Directory(p.join(root.path, 'nope')));

    expect(usage.fileCount, 0);
    expect(usage.bytes, 0);
    expect(usage.label, '0 file · 0,0 MB');
  });

  test('sums files recursively, thumbnails included', () async {
    File(p.join(root.path, 'IMG_1.jpg'))
        .writeAsBytesSync(List.filled(1024 * 1024, 7));
    final thumbs = Directory(p.join(root.path, 'thumbnails'))
      ..createSync(recursive: true);
    File(p.join(thumbs.path, 'IMG_1_thumb.jpg'))
        .writeAsBytesSync(List.filled(512 * 1024, 7));

    final usage = await PhotoDirUsage.measure(root);

    expect(usage.fileCount, 2);
    expect(usage.bytes, 1024 * 1024 + 512 * 1024);
    expect(usage.label, '2 file · 1,5 MB');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/photo_dir_usage_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/services/photo/photo_dir_usage.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/services/photo/photo_dir_usage.dart`:

```dart
import 'dart:io';

/// Disk usage of the photo directory, shown in Settings (Specifiche.md §11:
/// `Directory.stat()` does NOT report content size — the files must be
/// iterated and summed). Computed on demand (first section load + refresh
/// button), never polled.
class PhotoDirUsage {
  const PhotoDirUsage({required this.fileCount, required this.bytes});

  final int fileCount;
  final int bytes;

  static const PhotoDirUsage empty = PhotoDirUsage(fileCount: 0, bytes: 0);

  /// e.g. `12 file · 8,4 MB` (Italian decimal comma, one decimal).
  String get label {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
    return '$fileCount file · $mb MB';
  }

  static Future<PhotoDirUsage> measure(Directory dir) async {
    if (!dir.existsSync()) return empty;
    var count = 0;
    var bytes = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      count++;
      bytes += await entity.length();
    }
    return PhotoDirUsage(fileCount: count, bytes: bytes);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/photo_dir_usage_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/photo/photo_dir_usage.dart test/photo_dir_usage_test.dart
git commit -m "feat: photo directory usage measurement for settings"
```

---

### Task 3: `PhotoDirMigrationService` — move photo files between base dirs

Copy every file to the new base dir preserving the relative structure, then delete the sources. On any copy failure: remove the copies, keep the sources, report an error. **No DB writes** — stored paths are relative to the base dir, so they stay valid.

**Files:**
- Create: `lib/services/photo/photo_dir_migration.dart`
- Test: `test/photo_dir_migration_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class MigrationResult { const MigrationResult.success(int movedFiles); const MigrationResult.failure(String error); final int movedFiles; final String? error; bool get ok; }`
  - `class PhotoDirMigrationService { const PhotoDirMigrationService(); Future<MigrationResult> migrate({required Directory from, required Directory to}); }`

- [ ] **Step 1: Write the failing tests**

Create `test/photo_dir_migration_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/photo_dir_migration_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/services/photo/photo_dir_migration.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/services/photo/photo_dir_migration.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

/// Outcome of a photo-directory migration. [error] is a ready-to-show
/// Italian message; the caller owns the SnackBar.
class MigrationResult {
  const MigrationResult.success(this.movedFiles) : error = null;
  const MigrationResult.failure(this.error) : movedFiles = 0;

  final int movedFiles;
  final String? error;

  bool get ok => error == null;
}

/// Moves the photo files when the user changes the photo directory in
/// Settings. Copy-all-then-delete, never a half state: if one copy fails the
/// copies are removed and the source files stay where they are.
///
/// The `foto` table stores paths RELATIVE to the photo base dir
/// (FotoRepository.basePathProvider), so moving the files keeps every stored
/// path valid — this service performs no DB write at all.
class PhotoDirMigrationService {
  const PhotoDirMigrationService();

  Future<MigrationResult> migrate({
    required Directory from,
    required Directory to,
  }) async {
    if (!from.existsSync() || p.equals(from.path, to.path)) {
      return const MigrationResult.success(0);
    }

    final sources = from.listSync(recursive: true).whereType<File>().toList();
    final copies = <File>[];
    try {
      for (final source in sources) {
        final relative = p.relative(source.path, from: from.path);
        final target = File(p.join(to.path, relative));
        await target.parent.create(recursive: true);
        await source.copy(target.path);
        copies.add(target);
      }
    } on FileSystemException {
      for (final copy in copies) {
        try {
          if (copy.existsSync()) await copy.delete();
        } on FileSystemException {
          // [NON-BLOCKING] a leftover copy wastes space; the source files
          // are still intact, which is what correctness depends on.
        }
      }
      return const MigrationResult.failure(
          'Spostamento non riuscito: le foto sono rimaste nella cartella precedente.');
    }

    for (final source in sources) {
      try {
        if (source.existsSync()) await source.delete();
      } on FileSystemException {
        // [NON-BLOCKING] same reasoning as FotoRepository.deleteFiles: the
        // copies are already in place, an undeleted original is recoverable.
      }
    }
    return MigrationResult.success(copies.length);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/photo_dir_migration_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/photo/photo_dir_migration.dart test/photo_dir_migration_test.dart
git commit -m "feat: photo directory migration with clean abort"
```

---

### Task 4: `BackupService.createBackup` + `uploadToDrive` stub

Zip `nota_spese.db` and the whole photo dir into a timestamped temp file; the caller shares it. Partial zips are never left behind.

**Files:**
- Create: `lib/services/backup/backup_service.dart`
- Test: `test/backup_service_test.dart`

**Interfaces:**
- Consumes: `DbHelper.dbFileName`, `DbHelper.expectedTables`, `DbHelper.databasePath()` (Task 1).
- Produces:
  - `class BackupService { BackupService({required Future<String> Function() dbPathProvider, required Future<Directory> Function() photoDirProvider, required Future<void> Function() closeDatabase, Future<Directory> Function()? tempDirProvider, DatabaseFactory? dbFactory, DateTime Function()? now}); static const String photoEntryDir = 'foto'; static String backupFileName(DateTime now); Future<File> createBackup(); Future<void> uploadToDrive(); }`
  - `restoreBackup` and `RestoreResult` arrive in Task 5.

- [ ] **Step 1: Write the failing tests**

Create `test/backup_service_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/backup_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/services/backup/backup_service.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/services/backup/backup_service.dart`:

```dart
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
        _closeDatabase = closeDatabase,
        _tempDir = tempDirProvider ?? getTemporaryDirectory,
        _dbFactory = dbFactory,
        _now = now ?? DateTime.now;

  final Future<String> Function() _dbPath;
  final Future<Directory> Function() _photoDir;
  final Future<void> Function() _closeDatabase;
  final Future<Directory> Function() _tempDir;
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/backup_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/backup_service.dart test/backup_service_test.dart
git commit -m "feat: backup zip creation with drive upload stub"
```

---

### Task 5: `BackupService.restoreBackup` — validate, swap atomically, roll back

Extract to a temp dir, refuse anything that isn't a nota_spese DB, then swap DB + photo dir behind `.bak` copies that are deleted only on success.

**Files:**
- Modify: `lib/services/backup/backup_service.dart`
- Test: `test/backup_service_test.dart` (add a `group`)

**Interfaces:**
- Consumes: `BackupService` (Task 4), `DbHelper.expectedTables`, `DbHelper.dbFileName`.
- Produces:
  - `class RestoreResult { const RestoreResult.success(); const RestoreResult.failure(String error); final String? error; bool get ok; }`
  - `BackupService.restoreBackup(File zip) → Future<RestoreResult>` — on `ok` the current DB connection is closed and the caller must show the "riavvia l'app" dialog; on failure the current data is untouched.

- [ ] **Step 1: Write the failing tests**

Add to `test/backup_service_test.dart` — extend the imports and append the group before the closing `}` of `main()`:

```dart
// add to the existing imports
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
```

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/backup_service_test.dart`
Expected: FAIL — `The method 'restoreBackup' isn't defined for the class 'BackupService'`.

- [ ] **Step 3: Write the implementation**

In `lib/services/backup/backup_service.dart`, add the result class above `BackupService`:

```dart
/// Outcome of a restore. [error] is a ready-to-show Italian message; the
/// caller owns the dialog/SnackBar.
class RestoreResult {
  const RestoreResult.success() : error = null;
  const RestoreResult.failure(this.error);

  final String? error;

  bool get ok => error == null;
}
```

Then add, after `createBackup()`:

```dart
  /// Extracts [zip], refuses anything that isn't a nota_spese DB, and only
  /// then swaps the live DB + photo dir. Current data survives every failure
  /// path: the previous files are parked as `.bak` / `_bak` and restored if
  /// the swap breaks halfway. On success the DB connection is closed and the
  /// caller shows the "riavvia l'app" dialog.
  Future<RestoreResult> restoreBackup(File zip) async {
    final tempRoot = Directory(p.join((await _tempDir()).path,
        'restore_${_now().millisecondsSinceEpoch}'));
    try {
      await tempRoot.create(recursive: true);
      try {
        await extractFileToDisk(zip.path, tempRoot.path);
      } catch (_) {
        return const RestoreResult.failure(
            'Archivio non leggibile: zip corrotto o non valido.');
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

      return _swapIn(
          extractedDb, Directory(p.join(tempRoot.path, photoEntryDir)));
    } finally {
      try {
        if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
      } on FileSystemException {
        // [NON-BLOCKING] temp leftovers cost space, nothing else; the OS
        // clears the cache dir eventually.
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

  Future<RestoreResult> _swapIn(File newDb, Directory newPhotos) async {
    final dbPath = await _dbPath();
    final photoDir = await _photoDir();
    final dbBak = File('$dbPath.bak');
    final photoBak = Directory('${photoDir.path}_bak');

    await _closeDatabase();
    if (dbBak.existsSync()) await dbBak.delete();
    if (photoBak.existsSync()) await photoBak.delete(recursive: true);

    var dbParked = false;
    var photosParked = false;
    try {
      final currentDb = File(dbPath);
      if (currentDb.existsSync()) {
        await currentDb.rename(dbBak.path);
        dbParked = true;
      }
      if (photoDir.existsSync()) {
        await photoDir.rename(photoBak.path);
        photosParked = true;
      }

      await Directory(p.dirname(dbPath)).create(recursive: true);
      await _moveFile(newDb, dbPath);
      if (newPhotos.existsSync()) {
        await _moveDirectory(newPhotos, photoDir.path);
      } else {
        await photoDir.create(recursive: true);
      }

      if (dbParked) await dbBak.delete();
      if (photosParked) await photoBak.delete(recursive: true);
      return const RestoreResult.success();
    } catch (_) {
      await _rollback(
        dbPath: dbPath,
        dbBak: dbBak,
        dbParked: dbParked,
        photoDir: photoDir,
        photoBak: photoBak,
        photosParked: photosParked,
      );
      return const RestoreResult.failure(
          'Ripristino non completato: i dati precedenti sono stati mantenuti.');
    }
  }

  Future<void> _rollback({
    required String dbPath,
    required File dbBak,
    required bool dbParked,
    required Directory photoDir,
    required Directory photoBak,
    required bool photosParked,
  }) async {
    try {
      final halfDb = File(dbPath);
      if (dbParked && halfDb.existsSync()) await halfDb.delete();
      if (photosParked && photoDir.existsSync()) {
        await photoDir.delete(recursive: true);
      }
      if (dbParked && dbBak.existsSync()) await dbBak.rename(dbPath);
      if (photosParked && photoBak.existsSync()) {
        await photoBak.rename(photoDir.path);
      }
    } on FileSystemException {
      // [NON-BLOCKING] best effort: the .bak copies stay on disk so the data
      // is recoverable by hand instead of silently lost.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/backup_service_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/backup_service.dart test/backup_service_test.dart
git commit -m "feat: backup restore with schema validation and rollback"
```

---

### Task 6: `ImpostazioniScreen` replaces `ImpostazioniMinimal`

Move the existing OCR / API key / exchange-rate / version UI into the new screen unchanged (same widget keys, same behaviour), wire it into the shell, delete `ImpostazioniMinimal`, and relocate its widget tests to a dedicated file. No behaviour change in this task — sections Foto and Backup arrive in Tasks 7 and 8.

**Files:**
- Create: `lib/ui/impostazioni/impostazioni_screen.dart`
- Modify: `lib/ui/shell/home_shell.dart` (use the new screen, delete `ImpostazioniMinimal`, drop the now-unused `OcrEngine` import if analyze flags it)
- Create: `test/impostazioni_screen_test.dart`
- Modify: `test/home_shell_test.dart` (drop the settings-detail groups, keep the tab-wiring test)

**Interfaces:**
- Consumes: `ApiKeyStore` (`read/write/delete`), `SettingsService` (`ocrEngineDefault`, `setOcrEngineDefault`, `tassiOnline`, `setTassiOnline`), `appVersion`.
- Produces: `class ImpostazioniScreen extends StatefulWidget { const ImpostazioniScreen({super.key, required ApiKeyStore apiKeyStore, required SettingsService settingsService}); }` — widget keys kept from `ImpostazioniMinimal`: `campo-api-key`, `salva-api-key`, `rimuovi-api-key`, `motore-default`, `toggle-tassi-online`.

- [ ] **Step 1: Write the failing test**

Create `test/impostazioni_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/settings/api_key_store.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/impostazioni/impostazioni_screen.dart';
import 'package:nota_spese/version.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory fake: ApiKeyStore wraps FlutterSecureStorage, not host-testable
/// (see its class doc), so tests override the three methods.
class _FakeApiKeyStore extends ApiKeyStore {
  _FakeApiKeyStore([this._value]);

  String? _value;
  String? written;
  bool deleted = false;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    written = value;
    _value = value;
  }

  @override
  Future<void> delete() async {
    deleted = true;
    _value = null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    ApiKeyStore? apiKeyStore,
    SettingsService? settingsService,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ImpostazioniScreen(
        apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
        settingsService: settingsService ?? SettingsService(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the sections and the app version', (tester) async {
    await pump(tester);

    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.byKey(const Key('campo-api-key')), findsOneWidget);
    expect(find.byKey(const Key('motore-default')), findsOneWidget);
    expect(find.byKey(const Key('toggle-tassi-online')), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining(appVersion),
      find.byType(Scrollable).last,
      const Offset(0, -100),
    );
    expect(find.textContaining(appVersion), findsOneWidget);
  });

  group('Claude API key', () {
    testWidgets('initial state is non configurata, no Rimuovi button',
        (tester) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
    });

    testWidgets('saving writes the value, shows configurata, clears field',
        (tester) async {
      final store = _FakeApiKeyStore();
      await pump(tester, apiKeyStore: store);

      await tester.enterText(
          find.byKey(const Key('campo-api-key')), 'sk-segreta-123');
      await tester.tap(find.byKey(const Key('salva-api-key')));
      await tester.pumpAndSettle();

      expect(store.written, 'sk-segreta-123');
      expect(find.text('Configurata'), findsOneWidget);
      final field =
          tester.widget<TextField>(find.byKey(const Key('campo-api-key')));
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('sk-segreta-123'), findsNothing);
    });

    testWidgets('removing the key reverts a claude default to mlkit',
        (tester) async {
      final settingsService = SettingsService();
      await settingsService.setOcrEngineDefault(OcrEngine.claude);
      final store = _FakeApiKeyStore('sk-esistente');
      await pump(tester,
          apiKeyStore: store, settingsService: settingsService);

      await tester.tap(find.byKey(const Key('rimuovi-api-key')));
      await tester.pumpAndSettle();

      expect(store.deleted, isTrue);
      expect(await settingsService.ocrEngineDefault, OcrEngine.mlkit);
      expect(find.text('Non configurata'), findsOneWidget);
    });
  });

  group('motore OCR predefinito', () {
    testWidgets('Claude segment disabled without a key', (tester) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      final button = tester.widget<SegmentedButton<OcrEngine>>(
          find.byKey(const Key('motore-default')));
      expect(button.segments.firstWhere((s) => s.value == OcrEngine.claude)
          .enabled, isFalse);
    });

    testWidgets('selecting Claude persists the default', (tester) async {
      final settingsService = SettingsService();
      await pump(tester,
          apiKeyStore: _FakeApiKeyStore('sk-esistente'),
          settingsService: settingsService);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('motore-default')),
          matching: find.text('Claude')));
      await tester.pumpAndSettle();

      expect(await settingsService.ocrEngineDefault, OcrEngine.claude);
    });
  });

  testWidgets('tassi online: default ON, tap persists OFF', (tester) async {
    await pump(tester);

    final toggle = find.byKey(const Key('toggle-tassi-online'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await SettingsService().tassiOnline, isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/impostazioni_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/ui/impostazioni/impostazioni_screen.dart'`.

- [ ] **Step 3: Create the screen**

Create `lib/ui/impostazioni/impostazioni_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../services/ocr/parsed_receipt.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';

/// Full settings screen (fase 8), replacing ImpostazioniMinimal: OCR engine +
/// Claude API key, photo options, exchange rates, backup/restore, version.
/// Services do the work and return results; every dialog and SnackBar lives
/// here.
class ImpostazioniScreen extends StatefulWidget {
  const ImpostazioniScreen({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
  });

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
  final _apiKeyController = TextEditingController();
  bool _configured = false;
  OcrEngine _engineDefault = OcrEngine.mlkit;
  bool _tassiOnline = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Cached once in initState, not re-fetched per build (gotcha: a fresh
  // Future in build would rebuild forever — pattern from
  // TrasfertaDetailScreen._loadOcrSettings).
  Future<void> _load() async {
    final key = await widget.apiKeyStore.read();
    final engine = await widget.settingsService.ocrEngineDefault;
    final tassi = await widget.settingsService.tassiOnline;
    if (!mounted) return;
    setState(() {
      _configured = key != null && key.isNotEmpty;
      _engineDefault = engine;
      _tassiOnline = tassi;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _salvaApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) return;
    await widget.apiKeyStore.write(value);
    _apiKeyController.clear();
    if (!mounted) return;
    setState(() => _configured = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Chiave API salvata.')));
  }

  Future<void> _rimuoviApiKey() async {
    await widget.apiKeyStore.delete();
    final revertToMlkit = _engineDefault == OcrEngine.claude;
    if (revertToMlkit) {
      await widget.settingsService.setOcrEngineDefault(OcrEngine.mlkit);
    }
    if (!mounted) return;
    setState(() {
      _configured = false;
      if (revertToMlkit) _engineDefault = OcrEngine.mlkit;
    });
  }

  Future<void> _onEngineChanged(Set<OcrEngine> selection) async {
    final engine = selection.first;
    await widget.settingsService.setOcrEngineDefault(engine);
    if (!mounted) return;
    setState(() => _engineDefault = engine);
  }

  Future<void> _onTassiOnlineChanged(bool value) async {
    await widget.settingsService.setTassiOnline(value);
    if (!mounted) return;
    setState(() => _tassiOnline = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sezioneOcr(context),
          const SizedBox(height: 16),
          _sezioneCambio(),
          const SizedBox(height: 16),
          Text(
            'Nota Spese v$appVersion',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _sezioneOcr(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OCR', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<OcrEngine>(
              key: const Key('motore-default'),
              segments: [
                const ButtonSegment(
                    value: OcrEngine.mlkit, label: Text('ML Kit')),
                ButtonSegment(
                  value: OcrEngine.claude,
                  label: const Text('Claude'),
                  enabled: _configured,
                ),
              ],
              selected: {_engineDefault},
              onSelectionChanged: _onEngineChanged,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('campo-api-key'),
              controller: _apiKeyController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Chiave API Claude Vision'),
            ),
            const SizedBox(height: 8),
            Text(_configured ? 'Configurata' : 'Non configurata'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  key: const Key('salva-api-key'),
                  onPressed: _salvaApiKey,
                  child: const Text('Salva'),
                ),
                if (_configured) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const Key('rimuovi-api-key'),
                    onPressed: _rimuoviApiKey,
                    child: const Text('Rimuovi'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sezioneCambio() {
    return Card(
      child: SwitchListTile(
        key: const Key('toggle-tassi-online'),
        title: const Text('Tassi di cambio online'),
        subtitle: const Text(
            'Conversione EUR automatica via frankfurter.app (tasso del giorno della spesa)'),
        value: _tassiOnline,
        onChanged: _onTassiOnlineChanged,
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the shell and delete `ImpostazioniMinimal`**

In `lib/ui/shell/home_shell.dart`:
1. Add the import `import '../impostazioni/impostazioni_screen.dart';` (keep imports alphabetically sorted: it goes after `../../version.dart`'s block, with the other `../` UI imports, before `../trasferte/...`).
2. Replace the third `IndexedStack` child:

```dart
          ImpostazioniScreen(
            apiKeyStore: widget.apiKeyStore,
            settingsService: widget.settingsService,
          ),
```

3. Delete the whole `ImpostazioniMinimal` class and `_ImpostazioniMinimalState` (everything from the `/// Minimal settings (fase 5): ...` doc comment to the end of the file).
4. Remove the now-unused imports flagged by analyze (`../../services/ocr/parsed_receipt.dart` and `../../version.dart` are only used by the deleted class).

- [ ] **Step 5: Trim `test/home_shell_test.dart` to shell wiring**

Delete these from `test/home_shell_test.dart`: the groups `Impostazioni — Claude API key` and `Impostazioni — motore OCR predefinito`, and the test `toggle tassi online: default ON, tap persiste OFF` (all three now live in `test/impostazioni_screen_test.dart`).

Replace the test `Impostazioni tab shows placeholder with version` with:

```dart
  testWidgets('Impostazioni tab shows the settings screen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(find.byType(ImpostazioniScreen), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining(appVersion),
      find.byType(Scrollable).last,
      const Offset(0, -100),
    );
    expect(find.textContaining(appVersion), findsOneWidget);
  });
```

Add the import `import 'package:nota_spese/ui/impostazioni/impostazioni_screen.dart';` and keep `_FakeApiKeyStore` (still used by `pump`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/impostazioni_screen_test.dart test/home_shell_test.dart`
Expected: PASS (9 + 3 tests).

- [ ] **Step 7: Verify analyze is clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/ui/impostazioni/impostazioni_screen.dart lib/ui/shell/home_shell.dart test/impostazioni_screen_test.dart test/home_shell_test.dart
git commit -m "feat: full settings screen replaces ImpostazioniMinimal"
```

---

### Task 7: Foto section — JPG quality, directory switch with migration, usage

Adds the "Foto" card: quality slider (50–90, "vale per le nuove foto"), photo dir selector whose change is gated by a **"Migra ora" / "Annulla"** dialog, and the space-used row with a refresh button.

**Files:**
- Modify: `lib/ui/impostazioni/impostazioni_screen.dart`
- Modify: `lib/ui/shell/home_shell.dart` (new `photoDirFor` param, forwarded)
- Modify: `lib/app.dart` (same param)
- Modify: `lib/main.dart` (extract `photoDirFor`, reuse it for `photoBasePath`)
- Modify: `test/impostazioni_screen_test.dart`
- Modify: `test/home_shell_test.dart` (pass the new param in `pump`)

**Interfaces:**
- Consumes: `SettingsService` (`jpgQuality`, `setJpgQuality`, `photoDirKind`, `setPhotoDirKind`, `minJpgQuality` 50, `maxJpgQuality` 90), `PhotoDirKind` (`internal`, `external`), `PhotoDirMigrationService.migrate({from, to}) → MigrationResult` (`ok`, `movedFiles`, `error`) (Task 3), `PhotoDirUsage.measure(Directory) → PhotoDirUsage` (`label`) (Task 2).
- Produces:
  - `ImpostazioniScreen` gains `required Future<Directory> Function(PhotoDirKind) photoDirFor` and `PhotoDirMigrationService migrationService = const PhotoDirMigrationService()`.
  - `HomeShell` / `NotaSpeseApp` gain `required Future<Directory> Function(PhotoDirKind) photoDirFor`.
  - New widget keys: `slider-qualita-jpg`, `selettore-dir-foto`, `spazio-usato`, `refresh-spazio`, `dialog-migrazione`, `conferma-migrazione`.

- [ ] **Step 1: Write the failing tests**

In `test/impostazioni_screen_test.dart`, extend the imports:

```dart
import 'dart:io';

import 'package:nota_spese/services/photo/photo_dir_migration.dart';
import 'package:path/path.dart' as p;
```

Add above `void main()`:

```dart
/// Always fails, to exercise the error path without touching the filesystem.
class _FailingMigrationService extends PhotoDirMigrationService {
  const _FailingMigrationService();

  @override
  Future<MigrationResult> migrate({
    required Directory from,
    required Directory to,
  }) async =>
      const MigrationResult.failure('Spostamento non riuscito: test.');
}
```

Replace the existing `pump` helper with one that also wires the photo dirs (the real `PhotoDirMigrationService` works on the host filesystem, so the happy path is tested end-to-end):

```dart
  late Directory root;
  late Directory internalDir;
  late Directory externalDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('impostazioni_test_');
    internalDir = Directory(p.join(root.path, 'interna', 'foto'))
      ..createSync(recursive: true);
    externalDir = Directory(p.join(root.path, 'esterna', 'foto'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    ApiKeyStore? apiKeyStore,
    SettingsService? settingsService,
    PhotoDirMigrationService migrationService =
        const PhotoDirMigrationService(),
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ImpostazioniScreen(
        apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
        settingsService: settingsService ?? SettingsService(),
        photoDirFor: (kind) async =>
            kind == PhotoDirKind.external ? externalDir : internalDir,
        migrationService: migrationService,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

Append this group before the closing `}` of `main()`:

```dart
  group('sezione Foto', () {
    testWidgets('quality slider starts at 70 and persists the new value',
        (tester) async {
      final settingsService = SettingsService();
      await pump(tester, settingsService: settingsService);

      final slider = find.byKey(const Key('slider-qualita-jpg'));
      await tester.ensureVisible(slider);
      expect(tester.widget<Slider>(slider).value, 70);

      // Drag to the far right: clamped at maxJpgQuality.
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(await settingsService.jpgQuality, SettingsService.maxJpgQuality);
      expect(find.textContaining('nuove foto'), findsOneWidget);
    });

    testWidgets('space used row shows the measured label', (tester) async {
      File(p.join(internalDir.path, 'IMG_1.jpg'))
          .writeAsBytesSync(List.filled(1024 * 1024, 3));
      await pump(tester);

      final row = find.byKey(const Key('spazio-usato'));
      await tester.ensureVisible(row);
      expect(find.textContaining('1 file · 1,0 MB'), findsOneWidget);

      File(p.join(internalDir.path, 'IMG_2.jpg'))
          .writeAsBytesSync(List.filled(1024 * 1024, 3));
      await tester.tap(find.byKey(const Key('refresh-spazio')));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 file · 2,0 MB'), findsOneWidget);
    });

    testWidgets('cancelling the dialog keeps dir and files unchanged',
        (tester) async {
      File(p.join(internalDir.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
      final settingsService = SettingsService();
      await pump(tester, settingsService: settingsService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(find.descendant(
          of: selector, matching: find.text('Esterna')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog-migrazione')), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.internal);
      expect(File(p.join(internalDir.path, 'IMG_1.jpg')).existsSync(), isTrue);
      expect(externalDir.existsSync(), isFalse);
    });

    testWidgets('confirming migrates the files and persists the new dir',
        (tester) async {
      File(p.join(internalDir.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
      final settingsService = SettingsService();
      await pump(tester, settingsService: settingsService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(find.descendant(
          of: selector, matching: find.text('Esterna')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.external);
      expect(File(p.join(externalDir.path, 'IMG_1.jpg')).readAsStringSync(),
          'photo-1');
      expect(File(p.join(internalDir.path, 'IMG_1.jpg')).existsSync(), isFalse);
      expect(find.text('1 foto spostata.'), findsOneWidget);
    });

    testWidgets('a failed migration keeps the previous dir and shows the error',
        (tester) async {
      final settingsService = SettingsService();
      await pump(tester,
          settingsService: settingsService,
          migrationService: const _FailingMigrationService());

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(find.descendant(
          of: selector, matching: find.text('Esterna')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.internal);
      expect(find.text('Spostamento non riuscito: test.'), findsOneWidget);
      expect(
          tester
              .widget<SegmentedButton<PhotoDirKind>>(selector)
              .selected,
          {PhotoDirKind.internal});
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/impostazioni_screen_test.dart`
Expected: FAIL — `No named parameter with the name 'photoDirFor'`.

- [ ] **Step 3: Add the section to the screen**

In `lib/ui/impostazioni/impostazioni_screen.dart`:

1. Extend the imports:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/ocr/parsed_receipt.dart';
import '../../services/photo/photo_dir_migration.dart';
import '../../services/photo/photo_dir_usage.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';
```

2. Extend the constructor and fields:

```dart
  const ImpostazioniScreen({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
    required this.photoDirFor,
    this.migrationService = const PhotoDirMigrationService(),
  });

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  /// Resolves the absolute photo dir of a [PhotoDirKind] (wired to main.dart);
  /// needed to migrate between the two and to measure disk usage.
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
  final PhotoDirMigrationService migrationService;
```

3. Add state fields next to the existing ones:

```dart
  int _jpgQuality = SettingsService.defaultJpgQuality;
  PhotoDirKind _dirKind = PhotoDirKind.internal;
  PhotoDirUsage _usage = PhotoDirUsage.empty;
  bool _migrating = false;
```

4. Extend `_load()` (keep the existing body, add the new reads at the end):

```dart
  Future<void> _load() async {
    final key = await widget.apiKeyStore.read();
    final engine = await widget.settingsService.ocrEngineDefault;
    final tassi = await widget.settingsService.tassiOnline;
    final quality = await widget.settingsService.jpgQuality;
    final dirKind = await widget.settingsService.photoDirKind;
    if (!mounted) return;
    setState(() {
      _configured = key != null && key.isNotEmpty;
      _engineDefault = engine;
      _tassiOnline = tassi;
      _jpgQuality = quality;
      _dirKind = dirKind;
    });
    await _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final usage =
        await PhotoDirUsage.measure(await widget.photoDirFor(_dirKind));
    if (!mounted) return;
    setState(() => _usage = usage);
  }
```

5. Add the handlers:

```dart
  Future<void> _onQualityChanged(double value) async {
    final quality = value.round();
    setState(() => _jpgQuality = quality);
    await widget.settingsService.setJpgQuality(quality);
  }

  /// The `foto` table stores paths relative to the photo base dir, so
  /// switching dir without moving the files would hide every existing photo:
  /// the change is only applied together with the migration (spec fase 8,
  /// amended 2026-07-25) — hence "Migra ora" or nothing.
  Future<void> _onDirKindChanged(Set<PhotoDirKind> selection) async {
    final target = selection.first;
    if (target == _dirKind || _migrating) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('dialog-migrazione'),
            title: const Text('Spostare le foto?'),
            content: const Text(
                'Le foto già salvate vengono spostate nella nuova cartella. '
                'Senza spostarle non sarebbero più visibili nell\'app.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const Key('conferma-migrazione'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Migra ora'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _migrating = true);
    final from = await widget.photoDirFor(_dirKind);
    final to = await widget.photoDirFor(target);
    final result =
        await widget.migrationService.migrate(from: from, to: to);
    if (!mounted) return;
    if (result.ok) {
      await widget.settingsService.setPhotoDirKind(target);
      if (!mounted) return;
      setState(() {
        _dirKind = target;
        _migrating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.movedFiles == 1
              ? '1 foto spostata.'
              : '${result.movedFiles} foto spostate.')));
      await _refreshUsage();
    } else {
      setState(() => _migrating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }
```

6. Insert `_sezioneFoto(context)` in `build`, between the OCR and Cambio cards:

```dart
          _sezioneOcr(context),
          const SizedBox(height: 16),
          _sezioneFoto(context),
          const SizedBox(height: 16),
          _sezioneCambio(),
```

7. Add the section builder:

```dart
  Widget _sezioneFoto(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Foto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Qualità JPG: $_jpgQuality%'),
            Slider(
              key: const Key('slider-qualita-jpg'),
              min: SettingsService.minJpgQuality.toDouble(),
              max: SettingsService.maxJpgQuality.toDouble(),
              divisions:
                  SettingsService.maxJpgQuality - SettingsService.minJpgQuality,
              label: '$_jpgQuality%',
              value: _jpgQuality.toDouble(),
              onChanged: _onQualityChanged,
            ),
            const Text('Vale per le nuove foto.'),
            const SizedBox(height: 16),
            const Text('Cartella foto'),
            const SizedBox(height: 8),
            SegmentedButton<PhotoDirKind>(
              key: const Key('selettore-dir-foto'),
              segments: const [
                ButtonSegment(
                    value: PhotoDirKind.internal, label: Text('Interna')),
                ButtonSegment(
                    value: PhotoDirKind.external, label: Text('Esterna')),
              ],
              selected: {_dirKind},
              onSelectionChanged: _migrating ? null : _onDirKindChanged,
            ),
            const SizedBox(height: 16),
            Row(
              key: const Key('spazio-usato'),
              children: [
                Expanded(child: Text('Spazio usato: ${_usage.label}')),
                IconButton(
                  key: const Key('refresh-spazio'),
                  onPressed: _refreshUsage,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Ricalcola',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: Wire the new param through shell, app and main**

`lib/ui/shell/home_shell.dart` — add to the constructor, fields, and the `ImpostazioniScreen` call:

```dart
    required this.photoDirFor,
```

```dart
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
```

```dart
          ImpostazioniScreen(
            apiKeyStore: widget.apiKeyStore,
            settingsService: widget.settingsService,
            photoDirFor: widget.photoDirFor,
          ),
```

Add `import 'dart:io';` at the top of the file (the `settings_service.dart` import already provides `PhotoDirKind`).

`lib/app.dart` — same three additions (`required this.photoDirFor,` in the constructor, the field, and `photoDirFor: photoDirFor,` in the `HomeShell` call), plus `import 'dart:io';`.

`lib/main.dart` — replace the `photoBasePath` closure with:

```dart
  // Single photo base dir shared by FotoRepository and PhotoService.
  // v1.0: app-specific dirs only (scoped storage, Specifiche.md §2);
  // external falls back to internal when unavailable.
  Future<Directory> photoDirFor(PhotoDirKind kind) async {
    final dir = kind == PhotoDirKind.external
        ? (await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, 'foto'));
  }

  Future<String> photoBasePath() async =>
      (await photoDirFor(await settingsService.photoDirKind)).path;
```

Add `import 'dart:io';` and pass `photoDirFor: photoDirFor,` to `NotaSpeseApp`.

- [ ] **Step 5: Fix `test/home_shell_test.dart`**

Add `photoDirFor` to the `HomeShell` built by `pump` (temp dir is enough — the settings section is only smoke-tested there):

```dart
        photoDirFor: (_) async => Directory.systemTemp,
```

Add the import `import 'package:nota_spese/services/settings/settings_service.dart';` if not already present (it is) — `dart:io` is already imported.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/impostazioni_screen_test.dart test/home_shell_test.dart`
Expected: PASS (14 + 3 tests).

- [ ] **Step 7: Verify the whole suite and analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/impostazioni/impostazioni_screen.dart lib/ui/shell/home_shell.dart lib/app.dart lib/main.dart test/impostazioni_screen_test.dart test/home_shell_test.dart
git commit -m "feat: settings photo section with quality, dir migration and usage"
```

---

### Task 8: Backup section — "Backup ora" and "Ripristina da backup"

Wires `BackupService` into the screen: backup goes to the share sheet (fase 7 pattern), restore picks a zip with `file_selector`, asks for explicit confirmation, and ends with the "riavvia l'app" dialog.

**Files:**
- Modify: `lib/ui/impostazioni/impostazioni_screen.dart`
- Modify: `lib/ui/shell/home_shell.dart` (new `backupService` param, forwarded)
- Modify: `lib/app.dart` (same param)
- Modify: `lib/main.dart` (build the `BackupService`)
- Modify: `test/impostazioni_screen_test.dart`
- Modify: `test/home_shell_test.dart` (pass the new param in `pump`)

**Interfaces:**
- Consumes: `BackupService.createBackup() → Future<File>`, `BackupService.restoreBackup(File) → Future<RestoreResult>` (`ok`, `error`) (Tasks 4–5), `DbHelper.databasePath` / `DbHelper.close` (Task 1), `XFile`/`SharePlus` (already used by `ExportService`), `file_selector.openFile`.
- Produces:
  - `ImpostazioniScreen` gains `required BackupService backupService`, `Future<XFile?> Function()? pickZip`, `Future<void> Function(XFile)? shareFile` (defaults: `file_selector.openFile` with a zip type group / `SharePlus.instance.share`).
  - `HomeShell` / `NotaSpeseApp` gain `required BackupService backupService`.
  - New widget keys: `backup-ora`, `ripristina-backup`, `dialog-conferma-restore`, `conferma-restore`, `dialog-riavvia`.

- [ ] **Step 1: Write the failing tests**

In `test/impostazioni_screen_test.dart` extend the imports:

```dart
// XFile comes from file_selector (a direct dependency): importing
// cross_file directly would trip depend_on_referenced_packages.
import 'package:file_selector/file_selector.dart';
import 'package:nota_spese/services/backup/backup_service.dart';
```

Add above `void main()`:

```dart
/// Records the calls and returns canned results. BackupService touches the
/// real filesystem/DB, so the widget tests use this instead (the constructor
/// still needs the required providers — they are never exercised).
class _FakeBackupService extends BackupService {
  _FakeBackupService({this.zip, this.restore = const RestoreResult.success()})
      : super(
          dbPathProvider: _unused,
          photoDirProvider: _unusedDir,
          closeDatabase: _noop,
        );

  static Future<String> _unused() async => '';
  static Future<Directory> _unusedDir() async => Directory.systemTemp;
  static Future<void> _noop() async {}

  final File? zip;
  final RestoreResult restore;
  int createCalls = 0;
  File? restored;

  @override
  Future<File> createBackup() async {
    createCalls++;
    final file = zip;
    if (file == null) throw const FileSystemException('backup failed');
    return file;
  }

  @override
  Future<RestoreResult> restoreBackup(File zip) async {
    restored = zip;
    return restore;
  }
}
```

Extend `pump` with the backup wiring (keep everything already there):

```dart
  Future<void> pump(
    WidgetTester tester, {
    ApiKeyStore? apiKeyStore,
    SettingsService? settingsService,
    PhotoDirMigrationService migrationService =
        const PhotoDirMigrationService(),
    BackupService? backupService,
    Future<XFile?> Function()? pickZip,
    List<XFile>? shared,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ImpostazioniScreen(
        apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
        settingsService: settingsService ?? SettingsService(),
        photoDirFor: (kind) async =>
            kind == PhotoDirKind.external ? externalDir : internalDir,
        migrationService: migrationService,
        backupService: backupService ?? _FakeBackupService(),
        pickZip: pickZip ?? () async => null,
        shareFile: (file) async => shared?.add(file),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

Append this group before the closing `}` of `main()`:

```dart
  group('sezione Backup', () {
    testWidgets('Backup ora creates the zip and shares it', (tester) async {
      final zip = File(p.join(root.path, 'backup.zip'))
        ..writeAsStringSync('zip-bytes');
      final service = _FakeBackupService(zip: zip);
      final shared = <XFile>[];
      await pump(tester, backupService: service, shared: shared);

      final button = find.byKey(const Key('backup-ora'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.createCalls, 1);
      expect(shared.single.path, zip.path);
    });

    testWidgets('a failing backup shows an error SnackBar', (tester) async {
      await pump(tester, backupService: _FakeBackupService());

      final button = find.byKey(const Key('backup-ora'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Backup non riuscito.'), findsOneWidget);
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final service = _FakeBackupService();
      await pump(tester,
          backupService: service, pickZip: () async => null);

      final button = find.byKey(const Key('ripristina-backup'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.restored, isNull);
      expect(find.byKey(const Key('dialog-conferma-restore')), findsNothing);
    });

    testWidgets('a successful restore ends with the restart dialog',
        (tester) async {
      final zip = File(p.join(root.path, 'from_user.zip'))
        ..writeAsStringSync('zip-bytes');
      final service = _FakeBackupService();
      await pump(tester,
          backupService: service, pickZip: () async => XFile(zip.path));

      final button = find.byKey(const Key('ripristina-backup'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog-conferma-restore')), findsOneWidget);
      expect(find.textContaining('sovrascrive'), findsOneWidget);
      await tester.tap(find.byKey(const Key('conferma-restore')));
      await tester.pumpAndSettle();

      expect(service.restored!.path, zip.path);
      expect(find.byKey(const Key('dialog-riavvia')), findsOneWidget);
      expect(find.textContaining('riavvia'), findsOneWidget);
    });

    testWidgets('declining the confirmation leaves the data alone',
        (tester) async {
      final zip = File(p.join(root.path, 'from_user2.zip'))
        ..writeAsStringSync('zip-bytes');
      final service = _FakeBackupService();
      await pump(tester,
          backupService: service, pickZip: () async => XFile(zip.path));

      final button = find.byKey(const Key('ripristina-backup'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(service.restored, isNull);
      expect(find.byKey(const Key('dialog-riavvia')), findsNothing);
    });

    testWidgets('a failed restore shows the service error', (tester) async {
      final zip = File(p.join(root.path, 'bad.zip'))
        ..writeAsStringSync('not-a-zip');
      final service = _FakeBackupService(
          restore: const RestoreResult.failure('Archivio non leggibile.'));
      await pump(tester,
          backupService: service, pickZip: () async => XFile(zip.path));

      final button = find.byKey(const Key('ripristina-backup'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-restore')));
      await tester.pumpAndSettle();

      expect(find.text('Archivio non leggibile.'), findsOneWidget);
      expect(find.byKey(const Key('dialog-riavvia')), findsNothing);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/impostazioni_screen_test.dart`
Expected: FAIL — `No named parameter with the name 'backupService'`.

- [ ] **Step 3: Add the section to the screen**

In `lib/ui/impostazioni/impostazioni_screen.dart`:

1. Extend the imports:

```dart
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup/backup_service.dart';
```

(`XFile` comes from `file_selector`/`share_plus`; both re-export `cross_file`.)

2. Extend the constructor and fields:

```dart
  ImpostazioniScreen({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
    required this.photoDirFor,
    required this.backupService,
    this.migrationService = const PhotoDirMigrationService(),
    Future<XFile?> Function()? pickZip,
    Future<void> Function(XFile)? shareFile,
  })  : pickZip = pickZip ?? _pickZipFile,
        shareFile = shareFile ??
            ((file) => SharePlus.instance.share(ShareParams(files: [file])));

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
  final BackupService backupService;
  final PhotoDirMigrationService migrationService;

  /// Injected so the backup/restore flow is host-testable: the real
  /// implementations are platform channels (pattern: ExportService).
  final Future<XFile?> Function() pickZip;
  final Future<void> Function(XFile) shareFile;

  static Future<XFile?> _pickZipFile() => openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
              label: 'Backup zip',
              extensions: ['zip'],
              mimeTypes: ['application/zip']),
        ],
      );
```

Note: the `const` on the constructor goes away (the defaults are computed) — that is fine, no caller uses it in a const context.

3. Add the state field:

```dart
  bool _backupRunning = false;
```

4. Add the handlers:

```dart
  Future<void> _backupOra() async {
    if (_backupRunning) return;
    setState(() => _backupRunning = true);
    try {
      final zip = await widget.backupService.createBackup();
      await widget.shareFile(XFile(zip.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup non riuscito.')));
      }
    } finally {
      if (mounted) setState(() => _backupRunning = false);
    }
  }

  Future<void> _ripristinaBackup() async {
    final picked = await widget.pickZip();
    if (picked == null || !mounted) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('dialog-conferma-restore'),
            title: const Text('Ripristinare il backup?'),
            content: const Text(
                'Il ripristino sovrascrive i dati attuali (trasferte, spese e foto). '
                'L\'operazione non è annullabile.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const Key('conferma-restore'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ripristina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _backupRunning = true);
    final result =
        await widget.backupService.restoreBackup(File(picked.path));
    if (!mounted) return;
    setState(() => _backupRunning = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    // No RestartWidget in v1.0 (spec decision 4): the DB connection is closed
    // and the in-memory controllers are stale, so ask for a restart.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('dialog-riavvia'),
        title: const Text('Backup ripristinato'),
        content: const Text('Chiudi e riavvia l\'app per vedere i dati ripristinati.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
  }
```

5. Insert `_sezioneBackup(context)` in `build`, between the Cambio card and the version footer:

```dart
          _sezioneCambio(),
          const SizedBox(height: 16),
          _sezioneBackup(context),
          const SizedBox(height: 16),
          Text(
            'Nota Spese v$appVersion',
```

6. Add the section builder:

```dart
  Widget _sezioneBackup(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'Un unico file zip con database e foto, da condividere o salvare dove vuoi.'),
            const SizedBox(height: 8),
            if (_backupRunning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            Row(
              children: [
                ElevatedButton(
                  key: const Key('backup-ora'),
                  onPressed: _backupRunning ? null : _backupOra,
                  child: const Text('Backup ora'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('ripristina-backup'),
                  onPressed: _backupRunning ? null : _ripristinaBackup,
                  child: const Text('Ripristina da backup'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: Wire `BackupService` through shell, app and main**

`lib/ui/shell/home_shell.dart` — add `required this.backupService,` to the constructor, the field `final BackupService backupService;`, the import `import '../../services/backup/backup_service.dart';`, and `backupService: widget.backupService,` in the `ImpostazioniScreen` call.

`lib/app.dart` — same additions plus `backupService: backupService,` in the `HomeShell` call.

`lib/main.dart` — after the `apiKeyStore` line, build the service and pass it to `NotaSpeseApp`:

```dart
  final backupService = BackupService(
    dbPathProvider: dbHelper.databasePath,
    photoDirProvider: () async => Directory(await photoBasePath()),
    closeDatabase: dbHelper.close,
  );
```

```dart
    backupService: backupService,
```

Add `import 'services/backup/backup_service.dart';`.

- [ ] **Step 5: Fix `test/home_shell_test.dart`**

Add to the `HomeShell` built by `pump`:

```dart
        backupService: BackupService(
          dbPathProvider: () async => p.join(Directory.systemTemp.path,
              'nota_spese_test.db'),
          photoDirProvider: () async => Directory.systemTemp,
          closeDatabase: dbHelper.close,
        ),
```

Add the imports `import 'package:nota_spese/services/backup/backup_service.dart';` and `import 'package:path/path.dart' as p;`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/impostazioni_screen_test.dart test/home_shell_test.dart`
Expected: PASS (20 + 3 tests).

- [ ] **Step 7: Verify the whole suite and analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/impostazioni/impostazioni_screen.dart lib/ui/shell/home_shell.dart lib/app.dart lib/main.dart test/impostazioni_screen_test.dart test/home_shell_test.dart
git commit -m "feat: settings backup section with share and restore flow"
```

---

### Task 9: Docs, gotcha and final verification

Record what shipped, what was deliberately left out, and the two spec amendments; then run the full verification gate.

**Files:**
- Modify: `ToDo.md` (fase 8 section, lines 212–226)
- Modify: `Specifiche.md` (dependency table line 29, §9 restore note line 392, §2 photo-path note)
- Modify: `CLAUDE.md` (Gotcha noti)

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: no code.

- [ ] **Step 1: Update `ToDo.md`**

Tick the implemented items in the fase 8 block and annotate the two that are out of scope, so the section reads:

```markdown
## Fase 8 — Impostazioni + Backup/Restore ✅
- [x] Schermata Impostazioni completa (`lib/ui/impostazioni/impostazioni_screen.dart`, sostituisce `ImpostazioniMinimal`): motore OCR default (ML Kit / Claude Vision), API key, cartella foto, qualità JPG, spazio usato, backup, toggle tassi online, versione app
- [x] Setting qualità JPG: slider 50–90 (default 70), persistito in `SharedPreferences`, letto da `photo_service.dart`; nota UI "vale per le nuove foto"
- [ ] ~~Gestione modello IA locale~~ — **fuori scope fase 8** (decisione 2026-07-25): nessun `LocalAiOcrService` esiste, gate benchmark fase 5 non superato → nessuna UI di download/stato/eliminazione, l'indicatore spazio copre solo la cartella foto
- [x] API key Claude Vision: inserimento/modifica mascherata, `flutter_secure_storage` (invariato da fase 5)
- [x] Scelta directory foto con migrazione file esistenti (`PhotoDirMigrationService`, dialog "Migra ora"/"Annulla": i path in DB sono relativi alla base dir, cambiare cartella senza spostare le foto le renderebbe invisibili → nessuna opzione "lascia dove sono")
- [x] Indicatore spazio usato cartella foto (`PhotoDirUsage`: conteggio file + MB, ricalcolo on-demand)
- [x] `backup_service.dart`: zip `nota_spese.db` + cartella foto → share sheet; trigger manuale con progress
- [x] Restore da zip: estrazione in temp → validazione schema DB → swap con `.bak` + rollback → dialog "riavvia l'app" (no `RestartWidget`, decisione 2026-07-25)
- [x] Interfaccia `BackupService` con stub `uploadToDrive()` per v1.1 (lancia `UnimplementedError`)
- [x] Versione DB: hook `onUpgrade` no-op in `db_helper.dart` così un futuro bump non rompe le install esistenti (`dbVersion` resta 1: schema invariato in fase 8)

**Verifica fase 8**
- [ ] ~~Ciclo completo su emulatore~~ — **SKIP esplicito** (nessun emulatore su questa macchina, gotcha `CLAUDE.md`): compensato da `test/backup_service_test.dart` (create + restore valido/DB invalido/zip corrotto/rollback), `test/photo_dir_migration_test.dart` e `test/impostazioni_screen_test.dart`; collaudo reale rimandato a device fisico (stile fase 6b)
- [ ] API key salvata sopravvive al riavvio e non compare in SharedPreferences → verificabile solo su device (invariato da fase 5)
```

- [ ] **Step 2: Update `Specifiche.md`**

Replace the `file_picker` row of the dependency table (line 29):

```markdown
| `file_selector` | selezione zip per il restore (SAF) — sostituisce `file_picker`, incompatibile con `share_plus 13` (win32) | 8 |
```

In §9 (line 392) replace the `RestartWidget` note with:

```markdown
- Reload UI dopo il restore: **v1.0 usa il dialog "Backup ripristinato — riavvia l'app"** (decisione fase 8, 2026-07-25): la connessione DB viene chiusa dallo swap e i controller in memoria sono stale; `RestartWidget` resta un'opzione v1.1 (meno codice e meno rischio su un flusso non testabile su emulatore).
```

In §2 (photo storage, around line 336) add:

```markdown
- **Path in DB relativi alla directory foto** (`FotoRepository.basePathProvider`): cambiare directory senza spostare i file renderebbe invisibili tutte le foto esistenti → il cambio in Impostazioni è possibile solo con migrazione ("Migra ora"/"Annulla"), e la migrazione non tocca il DB perché i path relativi restano validi.
```

- [ ] **Step 3: Add the gotcha to `CLAUDE.md`**

Append to the "Gotcha noti" list:

```markdown
- **Path foto in DB relativi (verificato 2026-07-25):** `foto.file_path`/`thumb_path` sono relativi alla base dir risolta da `basePathProvider` (`IMG_<ts>.jpg`, `thumbnails/IMG_<ts>_thumb.jpg`), non assoluti. Spostare i file tra directory NON richiede update del DB; cambiare directory senza spostarli rompe tutte le foto esistenti (vincolo che ha eliminato l'opzione "lascia dove sono" in fase 8).
```

- [ ] **Step 4: Run the full verification gate**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (380 from fase 7 + ~30 new).

- [ ] **Step 5: Commit**

```bash
git add ToDo.md Specifiche.md CLAUDE.md
git commit -m "docs: phase 8 status, spec amendments and relative photo path gotcha"
```

---

## Note di esecuzione

- **Ordine obbligato:** Task 1 abilita 4–5 (path DB + tabelle attese) e 2–3; il wiring UI (6→7→8) tocca `home_shell.dart`/`app.dart`/`main.dart` in modo incrementale, quindi eseguire i task in sequenza evita conflitti sugli stessi file.
- **Verifica su device (fuori piano, da fare a mano quando c'è un telefono collegato):** backup → elimina una trasferta → restore → riavvio → dati e foto tornati; cambio cartella foto interna→esterna con foto esistenti → le miniature restano visibili.
- **Non fare:** nessuna gestione modello IA locale, nessun upload Drive, nessuna migrazione DB formale, nessun accesso SAF a directory arbitrarie (tutto fuori scope v1.0, vedi spec §Fuori scope).
