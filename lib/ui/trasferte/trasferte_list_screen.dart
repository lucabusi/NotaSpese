import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/foto_repository.dart';
import '../../data/repositories/spesa_repository.dart';
import '../../data/repositories/trasferta_repository.dart';
import '../../services/ocr/recognition_orchestrator.dart';
import '../../services/photo/photo_service.dart';
import '../../services/photo/receipt_capture_service.dart';
import '../../services/settings/settings_service.dart';
import '../shared/widgets/trip_card.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_detail_screen.dart';
import 'trasferta_form_screen.dart';
import 'trasferte_list_controller.dart';

/// Trip list, used by both the "Trasferte" tab (controller.archiviate ==
/// false: total header + FAB) and the "Archivio" tab (archiviate == true).
class TrasferteListScreen extends StatefulWidget {
  const TrasferteListScreen({
    super.key,
    required this.controller,
    required this.trasfertaRepository,
    required this.spesaRepository,
    required this.fotoRepository,
    required this.photoService,
    required this.captureService,
    required this.orchestrator,
    required this.settingsService,
  });

  final TrasferteListController controller;
  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;
  final FotoRepository fotoRepository;
  final PhotoService photoService;
  final ReceiptCaptureService captureService;
  final RecognitionOrchestrator orchestrator;
  final SettingsService settingsService;

  @override
  State<TrasferteListScreen> createState() => _TrasferteListScreenState();
}

class _TrasferteListScreenState extends State<TrasferteListScreen> {
  TrasferteListController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  Future<void> _openForm() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrasfertaFormScreen(onSave: controller.create),
    ));
    await controller.load();
  }

  Future<void> _openDetail(int trasfertaId) async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => TrasfertaDetailScreen(
        controller: TrasfertaDetailController(
            trasfertaId,
            widget.trasfertaRepository,
            widget.spesaRepository,
            widget.fotoRepository,
            widget.photoService),
        captureService: widget.captureService,
        orchestrator: widget.orchestrator,
        settingsService: widget.settingsService,
      ),
    ));
    await controller.load();
  }

  Future<void> _elimina(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la trasferta?'),
        content:
            const Text('Verranno eliminate anche tutte le spese e le foto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed == true) await controller.elimina(id);
  }

  @override
  Widget build(BuildContext context) {
    final archivio = controller.archiviate;
    return Scaffold(
      appBar: AppBar(title: Text(archivio ? 'Archivio' : 'Trasferte')),
      floatingActionButton: archivio
          ? null
          : FloatingActionButton(
              onPressed: _openForm,
              child: const Icon(Symbols.add),
            ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.loading && controller.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.items.isEmpty) {
            return _EmptyState(archivio: archivio, onCreate: _openForm);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!archivio) ...[
                _TotalHeader(totale: controller.totaleComplessivoEur),
                const SizedBox(height: 12),
              ],
              for (final item in controller.items)
                TripCard(
                  item: item,
                  onTap: () => _openDetail(item.trasferta.id!),
                  onArchivia: () =>
                      controller.setArchiviata(item.trasferta.id!, true),
                  onRipristina: () =>
                      controller.setArchiviata(item.trasferta.id!, false),
                  onElimina: () => _elimina(item.trasferta.id!),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.totale});

  final double totale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Totale complessivo',
                style: textTheme.labelLarge
                    ?.copyWith(color: AppColors.textSecondary)),
            Text(
              formatEur(totale),
              style: textTheme.titleLarge?.copyWith(
                fontFeatures: amountFontFeatures,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archivio, required this.onCreate});

  final bool archivio;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.flight_takeoff,
              size: 56, color: AppColors.textTertiaryLight),
          const SizedBox(height: 12),
          Text(
            archivio ? 'Nessuna trasferta archiviata' : 'Nessuna trasferta',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!archivio) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Symbols.add),
              label: const Text('Crea la tua prima trasferta'),
            ),
          ],
        ],
      ),
    );
  }
}
