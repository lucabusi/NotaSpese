import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
