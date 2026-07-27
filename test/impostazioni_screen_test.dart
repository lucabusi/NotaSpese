import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// XFile comes from file_selector (a direct dependency): importing
// cross_file directly would trip depend_on_referenced_packages.
import 'package:file_selector/file_selector.dart';
import 'package:nota_spese/services/backup/backup_service.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/photo/photo_dir_migration.dart';
import 'package:nota_spese/services/settings/api_key_store.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:nota_spese/ui/impostazioni/impostazioni_screen.dart';
import 'package:nota_spese/version.dart';
import 'package:path/path.dart' as p;
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

/// Always fails, to exercise the error path without touching the filesystem.
class _FailingMigrationService extends PhotoDirMigrationService {
  const _FailingMigrationService();

  @override
  Future<MigrationResult> migrate({
    required Directory from,
    required Directory to,
  }) async => const MigrationResult.failure('Spostamento non riuscito: test.');
}

/// Completes only when the test says so, to inspect the screen mid-migration.
class _ControlledMigrationService extends PhotoDirMigrationService {
  _ControlledMigrationService();

  final completer = Completer<MigrationResult>();

  @override
  Future<MigrationResult> migrate({
    required Directory from,
    required Directory to,
  }) => completer.future;
}

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

/// Completes only when the test says so, to inspect the screen mid-backup.
class _ControlledBackupService extends _FakeBackupService {
  final completer = Completer<File>();

  @override
  Future<File> createBackup() {
    createCalls++;
    return completer.future;
  }
}

/// The settings ListView specifically: a bare `find.byType(ListView)` is unique
/// only while nothing else on screen is a list, and `find.byType(Scrollable)
/// .last` is the API key TextField's own horizontal scrollable.
final settingsList = find.descendant(
  of: find.byType(ImpostazioniScreen),
  matching: find.byType(ListView),
);

/// dart:io futures (`File.length`, `File.copy`) complete on the real event
/// loop, which the widget-test fake clock never drives — a plain
/// `pumpAndSettle` leaves the screen's file work hanging forever. Each real
/// turn advances one link of the chain, so alternate turns and pumps until
/// [until] matches; the caller's `expect` reports the failure if it never does.
Future<void> settleIo(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

void main() {
  late Directory root;
  late Directory internalDir;
  late Directory externalDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    Future<Directory> Function(PhotoDirKind)? photoDirFor,
    BackupService? backupService,
    Future<XFile?> Function()? pickZip,
    Future<void> Function(XFile)? shareFile,
    List<XFile>? shared,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImpostazioniScreen(
          apiKeyStore: apiKeyStore ?? _FakeApiKeyStore(),
          settingsService: settingsService ?? SettingsService(),
          photoDirFor:
              photoDirFor ??
              (kind) async =>
                  kind == PhotoDirKind.external ? externalDir : internalDir,
          migrationService: migrationService,
          backupService: backupService ?? _FakeBackupService(),
          pickZip: pickZip ?? () async => null,
          shareFile: shareFile ?? (file) async => shared?.add(file),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the sections and the app version', (tester) async {
    await pump(tester);

    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.byKey(const Key('campo-api-key')), findsOneWidget);
    expect(find.byKey(const Key('motore-default')), findsOneWidget);
    expect(find.byKey(const Key('slider-qualita-jpg')), findsOneWidget);
    // The Foto card pushed the rates toggle below the fold and the settings
    // ListView builds its children lazily: scroll before looking for it.
    await tester.dragUntilVisible(
      find.byKey(const Key('toggle-tassi-online')),
      settingsList,
      const Offset(0, -100),
    );
    expect(find.byKey(const Key('toggle-tassi-online')), findsOneWidget);
    // Scroll settings ListView to render version footer (pushed down by rates toggle card).
    await tester.dragUntilVisible(
      find.textContaining(appVersion),
      settingsList,
      const Offset(0, -100),
    );
    expect(find.textContaining(appVersion), findsOneWidget);
  });

  group('Claude API key', () {
    testWidgets('initial state is non configurata, no Rimuovi button', (
      tester,
    ) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.text('Configurata'), findsNothing);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
    });

    testWidgets('saving writes the value, shows configurata, clears field', (
      tester,
    ) async {
      final store = _FakeApiKeyStore();
      await pump(tester, apiKeyStore: store);

      await tester.enterText(
        find.byKey(const Key('campo-api-key')),
        'sk-segreta-123',
      );
      await tester.tap(find.byKey(const Key('salva-api-key')));
      await tester.pumpAndSettle();

      expect(store.written, 'sk-segreta-123');
      expect(find.text('Configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('campo-api-key')),
      );
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('sk-segreta-123'), findsNothing);
    });

    testWidgets('removing calls delete and reverts to non configurata', (
      tester,
    ) async {
      final store = _FakeApiKeyStore('sk-esistente');
      await pump(tester, apiKeyStore: store);

      expect(find.text('Configurata'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rimuovi-api-key')));
      await tester.pumpAndSettle();

      expect(store.deleted, isTrue);
      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
    });

    testWidgets('removing the key reverts a claude default to mlkit', (
      tester,
    ) async {
      final settingsService = SettingsService();
      await settingsService.setOcrEngineDefault(OcrEngine.claude);
      final store = _FakeApiKeyStore('sk-esistente');
      await pump(tester, apiKeyStore: store, settingsService: settingsService);

      final before = tester.widget<SegmentedButton<OcrEngine>>(
        find.byKey(const Key('motore-default')),
      );
      expect(before.selected, {OcrEngine.claude});

      await tester.tap(find.byKey(const Key('rimuovi-api-key')));
      await tester.pumpAndSettle();

      expect(store.deleted, isTrue);
      expect(await settingsService.ocrEngineDefault, OcrEngine.mlkit);
      expect(find.text('Non configurata'), findsOneWidget);
      expect(find.byKey(const Key('rimuovi-api-key')), findsNothing);
      final after = tester.widget<SegmentedButton<OcrEngine>>(
        find.byKey(const Key('motore-default')),
      );
      expect(after.selected, {OcrEngine.mlkit});
    });
  });

  group('motore OCR predefinito', () {
    testWidgets('Claude segment disabled without a key', (tester) async {
      await pump(tester, apiKeyStore: _FakeApiKeyStore());

      final button = tester.widget<SegmentedButton<OcrEngine>>(
        find.byKey(const Key('motore-default')),
      );
      expect(
        button.segments.firstWhere((s) => s.value == OcrEngine.claude).enabled,
        isFalse,
      );
    });

    testWidgets('selecting Claude persists the default', (tester) async {
      final settingsService = SettingsService();
      await pump(
        tester,
        apiKeyStore: _FakeApiKeyStore('sk-esistente'),
        settingsService: settingsService,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('motore-default')),
          matching: find.text('Claude'),
        ),
      );
      await tester.pumpAndSettle();

      expect(await settingsService.ocrEngineDefault, OcrEngine.claude);
      final button = tester.widget<SegmentedButton<OcrEngine>>(
        find.byKey(const Key('motore-default')),
      );
      expect(button.selected, {OcrEngine.claude});
    });
  });

  testWidgets('tassi online: default ON, tap persists OFF', (tester) async {
    await pump(tester);

    final toggle = find.byKey(const Key('toggle-tassi-online'));
    // Below the fold since the Foto card landed above it (lazy ListView).
    await tester.dragUntilVisible(toggle, settingsList, const Offset(0, -100));
    // dragUntilVisible stops as soon as the tile is built (cache extent), and
    // its closing ensureVisible only lands on the next frame: pump before tap.
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await SettingsService().tassiOnline, isFalse);
  });

  group('sezione Foto', () {
    testWidgets('quality slider starts at 70 and persists the new value', (
      tester,
    ) async {
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
      File(
        p.join(internalDir.path, 'IMG_1.jpg'),
      ).writeAsBytesSync(List.filled(1024 * 1024, 3));
      await pump(tester);

      final row = find.byKey(const Key('spazio-usato'));
      await tester.ensureVisible(row);
      final oneFile = find.textContaining('1 file · 1,0 MB');
      await settleIo(tester, oneFile);
      expect(oneFile, findsOneWidget);

      File(
        p.join(internalDir.path, 'IMG_2.jpg'),
      ).writeAsBytesSync(List.filled(1024 * 1024, 3));
      await tester.tap(find.byKey(const Key('refresh-spazio')));
      final twoFiles = find.textContaining('2 file · 2,0 MB');
      await settleIo(tester, twoFiles);

      expect(twoFiles, findsOneWidget);
    });

    testWidgets('cancelling the dialog keeps dir and files unchanged', (
      tester,
    ) async {
      File(p.join(internalDir.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
      final settingsService = SettingsService();
      await pump(tester, settingsService: settingsService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog-migrazione')), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.internal);
      expect(File(p.join(internalDir.path, 'IMG_1.jpg')).existsSync(), isTrue);
      expect(externalDir.existsSync(), isFalse);
    });

    testWidgets('confirming migrates the files and persists the new dir', (
      tester,
    ) async {
      File(p.join(internalDir.path, 'IMG_1.jpg')).writeAsStringSync('photo-1');
      // A photo already in the destination, so the refreshed usage label
      // (2 file) differs from the initial one (1 file): the test can settle on
      // the refresh itself instead of on the SnackBar, which the screen shows
      // *before* re-measuring — otherwise tearDown would delete the dirs with
      // that scan still running.
      externalDir.createSync(recursive: true);
      File(p.join(externalDir.path, 'IMG_0.jpg')).writeAsStringSync('photo-0');
      final settingsService = SettingsService();
      await pump(tester, settingsService: settingsService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      final refreshed = find.textContaining('2 file');
      await settleIo(tester, refreshed);

      expect(await settingsService.photoDirKind, PhotoDirKind.external);
      expect(
        File(p.join(externalDir.path, 'IMG_1.jpg')).readAsStringSync(),
        'photo-1',
      );
      expect(File(p.join(internalDir.path, 'IMG_1.jpg')).existsSync(), isFalse);
      expect(find.text('1 foto spostata.'), findsOneWidget);
      // The usage now measures the new dir, not the emptied one.
      expect(refreshed, findsOneWidget);
    });

    testWidgets('a failed migration keeps the previous dir and shows the error', (
      tester,
    ) async {
      final settingsService = SettingsService();
      await pump(
        tester,
        settingsService: settingsService,
        migrationService: const _FailingMigrationService(),
      );

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.internal);
      expect(find.text('Spostamento non riuscito: test.'), findsOneWidget);
      expect(
        tester.widget<SegmentedButton<PhotoDirKind>>(selector).selected,
        {PhotoDirKind.internal},
      );
    });

    testWidgets('a throwing collaborator leaves the selector usable', (
      tester,
    ) async {
      final settingsService = SettingsService();
      // Revoked external storage, dir removed underneath: neither photoDirFor
      // nor PhotoDirMigrationService is exception-total, and a throw used to
      // strand _migrating at true — with the screen living in HomeShell's
      // IndexedStack that killed the selector for the rest of the session.
      await pump(
        tester,
        settingsService: settingsService,
        photoDirFor: (kind) async => kind == PhotoDirKind.external
            ? throw const FileSystemException('cartella non disponibile')
            : internalDir,
      );

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      expect(await settingsService.photoDirKind, PhotoDirKind.internal);
      expect(
        find.text(
          'Spostamento non riuscito: le foto sono rimaste nella cartella precedente.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-spazio')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('selector and refresh are disabled while migrating', (
      tester,
    ) async {
      final migrationService = _ControlledMigrationService();
      await pump(tester, migrationService: migrationService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      final refresh = find.byKey(const Key('refresh-spazio'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      // Mid-migration: a second switch or a measure of the dir being emptied
      // would race the move.
      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNull,
      );
      expect(tester.widget<IconButton>(refresh).onPressed, isNull);

      migrationService.completer.complete(const MigrationResult.success(2));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNotNull,
      );
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      expect(find.text('2 foto spostate.'), findsOneWidget);
    });

    testWidgets('a move with nothing to move says so', (tester) async {
      // Happens for real when getExternalStorageDirectory() is unavailable and
      // both kinds resolve to the same dir: "0 foto spostate." would read as a
      // failure to a user whose photo dir is full.
      final migrationService = _ControlledMigrationService();
      await pump(tester, migrationService: migrationService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      migrationService.completer.complete(const MigrationResult.success(0));
      await tester.pumpAndSettle();

      expect(find.text('Nessuna foto da spostare.'), findsOneWidget);
      expect(find.text('0 foto spostate.'), findsNothing);
    });
  });

  group('sezione Backup', () {
    testWidgets('Backup ora creates the zip and shares it', (tester) async {
      final zip = File(p.join(root.path, 'backup.zip'))
        ..writeAsStringSync('zip-bytes');
      final service = _FakeBackupService(zip: zip);
      final shared = <XFile>[];
      await pump(tester, backupService: service, shared: shared);

      final button = find.byKey(const Key('backup-ora'));
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.createCalls, 1);
      expect(shared.single.path, zip.path);
    });

    testWidgets('a failing backup shows an error SnackBar', (tester) async {
      await pump(tester, backupService: _FakeBackupService());

      final button = find.byKey(const Key('backup-ora'));
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Backup non riuscito.'), findsOneWidget);
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final service = _FakeBackupService();
      await pump(tester,
          backupService: service, pickZip: () async => null);

      final button = find.byKey(const Key('ripristina-backup'));
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
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
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
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
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
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
      await tester.dragUntilVisible(button, settingsList, const Offset(0, -100));
      // dragUntilVisible stops as soon as the button is built (cache
      // extent), and its closing ensureVisible only lands on the next
      // frame: pump before tap (same gotcha as toggle-tassi-online above).
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-restore')));
      await tester.pumpAndSettle();

      expect(find.text('Archivio non leggibile.'), findsOneWidget);
      expect(find.byKey(const Key('dialog-riavvia')), findsNothing);
    });

    testWidgets('a throwing picker leaves the whole screen usable', (
      tester,
    ) async {
      // openFile is a platform channel: PlatformException on SAF/activity
      // errors, MissingPluginException when the plugin is missing. The
      // re-entrancy guard raises _backupRunning *before* that await, so an
      // unguarded throw stranded it at true — and the screen lives in
      // HomeShell's IndexedStack, whose State is never recreated, so both
      // backup buttons, the photo dir selector and the refresh button stayed
      // dead for the rest of the session, without even a SnackBar.
      await pump(
        tester,
        pickZip: () async =>
            throw PlatformException(code: 'channel-error', message: 'no SAF'),
      );

      final restore = find.byKey(const Key('ripristina-backup'));
      await tester.dragUntilVisible(
        restore,
        settingsList,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();

      expect(find.text('Ripristino non riuscito.'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(restore).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('backup-ora')))
            .onPressed,
        isNotNull,
      );

      // The photo controls sit above the Backup card: scroll back up.
      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.dragUntilVisible(
        selector,
        settingsList,
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-spazio')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('backup and restore are locked while a migration runs', (
      tester,
    ) async {
      // Not cosmetic: createBackup lists the photo dir recursively and then
      // adds one file at a time, so a concurrent copy-then-delete migration
      // deletes a file between the listing and its addFile and aborts the zip.
      final migrationService = _ControlledMigrationService();
      await pump(tester, migrationService: migrationService);

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.text('Esterna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conferma-migrazione')));
      await tester.pumpAndSettle();

      final backup = find.byKey(const Key('backup-ora'));
      final restore = find.byKey(const Key('ripristina-backup'));
      await tester.dragUntilVisible(
        backup,
        settingsList,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(backup).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNull);

      migrationService.completer.complete(const MigrationResult.success(2));
      await tester.pumpAndSettle();

      expect(tester.widget<ElevatedButton>(backup).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNotNull);
    });

    testWidgets('the photo dir is locked while a restore runs', (tester) async {
      // The mirror of the case above: _swapIn renames the whole photo dir, so
      // a migration started mid-restore would copy into a tree that is about
      // to be parked as _bak. The picker await is part of the guarded span.
      final picker = Completer<XFile?>();
      await pump(tester, pickZip: () => picker.future);

      final restore = find.byKey(const Key('ripristina-backup'));
      await tester.dragUntilVisible(
        restore,
        settingsList,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();

      final selector = find.byKey(const Key('selettore-dir-foto'));
      await tester.dragUntilVisible(
        selector,
        settingsList,
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-spazio')))
            .onPressed,
        isNull,
      );

      picker.complete(null);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<PhotoDirKind>>(selector)
            .onSelectionChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-spazio')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the progress bar runs only while the backup itself does', (
      tester,
    ) async {
      final service = _ControlledBackupService();
      await pump(tester, backupService: service);

      final backup = find.byKey(const Key('backup-ora'));
      await tester.dragUntilVisible(
        backup,
        settingsList,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(backup);
      // pump, never pumpAndSettle: an indeterminate progress indicator
      // animates forever and would hang it (that is the whole reason the bar
      // hangs off _backupWorking and not off the wider _backupRunning).
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      service.completer.complete(
        File(p.join(root.path, 'done.zip'))..writeAsStringSync('zip-bytes'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(service.createCalls, 1);
    });

    testWidgets('a failing share does not claim the backup failed', (
      tester,
    ) async {
      // The zip exists at that point: "Backup non riuscito." would send the
      // user retrying a backup that already succeeded.
      final zip = File(p.join(root.path, 'shared.zip'))
        ..writeAsStringSync('zip-bytes');
      await pump(
        tester,
        backupService: _FakeBackupService(zip: zip),
        shareFile: (_) async =>
            throw PlatformException(code: 'no-activity-found'),
      );

      final backup = find.byKey(const Key('backup-ora'));
      await tester.dragUntilVisible(
        backup,
        settingsList,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(backup);
      await tester.pumpAndSettle();

      expect(
        find.text('Backup creato ma condivisione non riuscita.'),
        findsOneWidget,
      );
      expect(find.text('Backup non riuscito.'), findsNothing);
    });
  });
}
