import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/repositories/foto_repository.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../services/currency/exchange_service.dart';
import '../../services/ocr/recognition_orchestrator.dart';
import '../../services/photo/crop_service.dart';
import '../../services/photo/photo_service.dart';
import '../../services/photo/receipt_capture_service.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../impostazioni/impostazioni_screen.dart';
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
          ImpostazioniScreen(
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

