import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/spesa.dart';
import '../../services/photo/receipt_capture_service.dart';
import '../spese/spesa_form_screen.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_form_screen.dart';

enum DetailAction { modifica, archivia, ripristina, elimina }

/// Trip detail (fase 2 skeleton): totals header, spese list (usually
/// empty until fase 3), FAB placeholder. Pops `true` after archive/delete
/// so the list screen reloads.
class TrasfertaDetailScreen extends StatefulWidget {
  const TrasfertaDetailScreen(
      {super.key, required this.controller, required this.captureService});

  final TrasfertaDetailController controller;
  final ReceiptCaptureService captureService;

  @override
  State<TrasfertaDetailScreen> createState() => _TrasfertaDetailScreenState();
}

class _TrasfertaDetailScreenState extends State<TrasfertaDetailScreen> {
  TrasfertaDetailController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _onAction(DetailAction action) async {
    switch (action) {
      case DetailAction.modifica:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TrasfertaFormScreen(
            initial: controller.trasferta,
            onSave: controller.updateTrasferta,
          ),
        ));
      case DetailAction.archivia:
        await controller.setArchiviata(true);
        if (mounted) Navigator.of(context).pop(true);
      case DetailAction.ripristina:
        await controller.setArchiviata(false);
        if (mounted) Navigator.of(context).pop(true);
      case DetailAction.elimina:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminare la trasferta?'),
            content: const Text(
                'Verranno eliminate anche tutte le spese e le foto.'),
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
        if (confirmed == true) {
          await controller.elimina();
          if (mounted) Navigator.of(context).pop(true);
        }
    }
  }

  Future<void> _openAddSheet() async {
    final scelta = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('sheet-scatta'),
              leading: const Icon(Symbols.photo_camera),
              title: const Text('Scatta scontrino'),
              subtitle: const Text('Scanner con ritaglio automatico'),
              onTap: () => Navigator.of(context).pop('scatta'),
            ),
            ListTile(
              key: const Key('sheet-manuale'),
              leading: const Icon(Symbols.edit),
              title: const Text('Inserimento manuale'),
              onTap: () => Navigator.of(context).pop('manuale'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (scelta == 'manuale') await _openSpesaForm();
    if (scelta == 'scatta') {
      final path = await _captureScatta();
      if (path != null && mounted) await _openSpesaForm(pendingFoto: path);
    }
  }

  /// Main path: ML Kit Document Scanner; picker camera as riserva
  /// (scanner API in beta / Play Services assenti).
  Future<String?> _captureScatta() async {
    try {
      return await widget.captureService.scanWithDocumentScanner();
    } catch (_) {
      return widget.captureService.pickFromCamera();
    }
  }

  /// "Aggiungi foto" from inside the form: choose the capture path.
  Future<String?> _pickFotoSource() async {
    final scelta = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('pick-scanner'),
              leading: const Icon(Symbols.document_scanner),
              title: const Text('Scanner documenti'),
              onTap: () => Navigator.of(context).pop('scanner'),
            ),
            ListTile(
              key: const Key('pick-camera'),
              leading: const Icon(Symbols.photo_camera),
              title: const Text('Fotocamera'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              key: const Key('pick-galleria'),
              leading: const Icon(Symbols.photo_library),
              title: const Text('Galleria'),
              onTap: () => Navigator.of(context).pop('galleria'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    try {
      return switch (scelta) {
        'scanner' => await widget.captureService.scanWithDocumentScanner(),
        'camera' => await widget.captureService.pickFromCamera(),
        'galleria' => await widget.captureService.pickFromGallery(),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSpesaForm({Spesa? spesa, String? pendingFoto}) async {
    final t = controller.trasferta;
    if (t == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SpesaFormScreen(
        trasfertaId: controller.trasfertaId,
        valutaDefault: t.valutaDefault,
        initial: spesa,
        initialFoto: spesa == null ? null : controller.fotoBySpesa[spesa.id],
        pendingFotoSourcePath: pendingFoto,
        onPickFoto: _pickFotoSource,
        photoPathResolver: controller.absolutePhotoPath,
        onSave: spesa == null
            ? (s, {nuovaFoto, rimuoviFoto = false}) =>
                controller.createSpesa(s, fotoSourcePath: nuovaFoto)
            : (s, {nuovaFoto, rimuoviFoto = false}) => controller.updateSpesa(
                s, fotoSourcePath: nuovaFoto, rimuoviFoto: rimuoviFoto),
        onDelete:
            spesa == null ? null : () => controller.deleteSpesa(spesa.id!),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.trasferta;
        return Scaffold(
          appBar: AppBar(
            title: Text(t?.nome ?? ''),
            actions: [
              PopupMenuButton<DetailAction>(
                onSelected: _onAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: DetailAction.modifica, child: Text('Modifica')),
                  if (t?.archiviata ?? false)
                    const PopupMenuItem(
                        value: DetailAction.ripristina,
                        child: Text('Ripristina'))
                  else
                    const PopupMenuItem(
                        value: DetailAction.archivia, child: Text('Archivia')),
                  const PopupMenuItem(
                      value: DetailAction.elimina, child: Text('Elimina')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _openAddSheet,
            child: const Icon(Symbols.add),
          ),
          body: controller.loading && t == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TotalsHeader(controller: controller),
                    if (controller.totaliEurPerCategoria.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CategoryTotals(
                          totali: controller.totaliEurPerCategoria),
                    ],
                    const SizedBox(height: 16),
                    if (controller.speseByData.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child:
                            Center(child: Text('Nessuna spesa registrata')),
                      )
                    else
                      for (final entry in controller.speseByData.entries) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            formatDate(entry.key),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                        for (final spesa in entry.value)
                          _SpesaTile(spesa,
                              thumbPath:
                                  controller.thumbAbsBySpesa[spesa.id],
                              onTap: () => _openSpesaForm(spesa: spesa)),
                      ],
                  ],
                ),
        );
      },
    );
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.controller});

  final TrasfertaDetailController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totale trasferta',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            Text(
              formatEur(controller.totaleEur),
              style: textTheme.headlineMedium?.copyWith(
                fontFeatures: amountFontFeatures,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (controller.countSenzaEur > 0)
              Text(
                '${controller.countSenzaEur} spese senza conversione EUR',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            if (controller.totaliPerValuta.length > 1 ||
                (controller.totaliPerValuta.isNotEmpty &&
                    !controller.totaliPerValuta.containsKey('EUR')))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  controller.totaliPerValuta.entries
                      .map((e) => '${e.key} ${formatImporto(e.value)}')
                      .join(' · '),
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-category EUR totals with proportional bars (mockup "barre").
class _CategoryTotals extends StatelessWidget {
  const _CategoryTotals({required this.totali});

  final Map<Categoria, double> totali;

  @override
  Widget build(BuildContext context) {
    final entries = totali.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totali per categoria (EUR)',
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(e.key.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: Text(e.key.label, style: textTheme.bodySmall),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : e.value / max,
                          minHeight: 6,
                          backgroundColor: AppColors.primaryContainer,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatEur(e.value),
                      style: textTheme.bodySmall?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpesaTile extends StatelessWidget {
  const _SpesaTile(this.spesa, {this.thumbPath, required this.onTap});

  final Spesa spesa;

  /// Absolute thumbnail path (resolved by the controller), null = no photo.
  final String? thumbPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = thumbPath;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: thumb != null
            ? ClipRRect(
                key: Key('tile-thumb-${spesa.id}'),
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(thumb),
                    width: 40, height: 40, fit: BoxFit.cover),
              )
            : Icon(spesa.categoria.icon, color: AppColors.primary),
        title: Text(spesa.fornitore ?? spesa.categoria.label),
        subtitle: Text(spesa.categoria.label),
        trailing: Text(
          '${spesa.valuta} ${formatImporto(spesa.importo)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFeatures: amountFontFeatures,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
