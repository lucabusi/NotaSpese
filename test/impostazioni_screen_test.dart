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
