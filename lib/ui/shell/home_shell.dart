import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/repositories/foto_repository.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../services/currency/exchange_service.dart';
import '../../services/ocr/parsed_receipt.dart';
import '../../services/ocr/recognition_orchestrator.dart';
import '../../services/photo/crop_service.dart';
import '../../services/photo/photo_service.dart';
import '../../services/photo/receipt_capture_service.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';
import '../trasferte/trasferte_list_controller.dart';
import '../trasferte/trasferte_list_screen.dart';

/// Root scaffold: NavigationBar with the three tabs from the mockup.
/// Tab switches reload the selected list so cross-tab mutations
/// (archive/restore) stay in sync.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.trasfertaRepository,
    required this.spesaRepository,
    required this.fotoRepository,
    required this.photoService,
    required this.captureService,
    required this.orchestrator,
    required this.settingsService,
    required this.apiKeyStore,
    required this.exchangeService,
    required this.cropService,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;
  final FotoRepository fotoRepository;
  final PhotoService photoService;
  final ReceiptCaptureService captureService;
  final RecognitionOrchestrator orchestrator;
  final SettingsService settingsService;
  final ApiKeyStore apiKeyStore;
  final ExchangeService exchangeService;
  final CropService cropService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final TrasferteListController _attiveController =
      TrasferteListController(widget.trasfertaRepository, widget.spesaRepository,
          archiviate: false);
  late final TrasferteListController _archivioController =
      TrasferteListController(widget.trasfertaRepository, widget.spesaRepository,
          archiviate: true);

  @override
  void dispose() {
    _attiveController.dispose();
    _archivioController.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    if (index == 0) _attiveController.load();
    if (index == 1) _archivioController.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TrasferteListScreen(
            controller: _attiveController,
            trasfertaRepository: widget.trasfertaRepository,
            spesaRepository: widget.spesaRepository,
            fotoRepository: widget.fotoRepository,
            photoService: widget.photoService,
            captureService: widget.captureService,
            orchestrator: widget.orchestrator,
            settingsService: widget.settingsService,
            exchangeService: widget.exchangeService,
            cropService: widget.cropService,
          ),
          TrasferteListScreen(
            controller: _archivioController,
            trasfertaRepository: widget.trasfertaRepository,
            spesaRepository: widget.spesaRepository,
            fotoRepository: widget.fotoRepository,
            photoService: widget.photoService,
            captureService: widget.captureService,
            orchestrator: widget.orchestrator,
            settingsService: widget.settingsService,
            exchangeService: widget.exchangeService,
            cropService: widget.cropService,
          ),
          ImpostazioniMinimal(
            apiKeyStore: widget.apiKeyStore,
            settingsService: widget.settingsService,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
              icon: Icon(Symbols.receipt_long), label: 'Trasferte'),
          NavigationDestination(icon: Icon(Symbols.archive), label: 'Archivio'),
          NavigationDestination(
              icon: Icon(Symbols.settings), label: 'Impostazioni'),
        ],
      ),
    );
  }
}

/// Minimal settings (fase 5): Claude API key + default OCR engine. The full
/// settings screen arrives in fase 8.
class ImpostazioniMinimal extends StatefulWidget {
  const ImpostazioniMinimal({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
  });

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  @override
  State<ImpostazioniMinimal> createState() => _ImpostazioniMinimalState();
}

class _ImpostazioniMinimalState extends State<ImpostazioniMinimal> {
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Claude API key',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('campo-api-key'),
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Chiave API'),
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
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Motore OCR predefinito',
                      style: Theme.of(context).textTheme.titleMedium),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              key: const Key('toggle-tassi-online'),
              title: const Text('Tassi di cambio online'),
              subtitle: const Text(
                  'Conversione EUR automatica via frankfurter.app (tasso del giorno della spesa)'),
              value: _tassiOnline,
              onChanged: _onTassiOnlineChanged,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Impostazioni — in arrivo (fase 8)\nNota Spese v$appVersion',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
