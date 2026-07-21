import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/spesa.dart';
import '../../data/models/trasferta.dart';
import '../../services/currency/exchange_service.dart';
import '../../services/ocr/parsed_receipt.dart';
import '../../services/ocr/recognition_orchestrator.dart';
import '../../services/photo/receipt_capture_service.dart';
import '../../services/settings/settings_service.dart';
import '../shared/currency_rows.dart';
import '../spese/ocr_progress.dart';
import '../spese/spesa_form_screen.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_form_screen.dart';

extension _OcrEngineLabel on OcrEngine {
  /// Sheet-row / picker label (spec: "ML Kit" / "Claude").
  String get label => this == OcrEngine.claude ? 'Claude' : 'ML Kit';
}

enum DetailAction { modifica, archivia, ripristina, elimina }

/// Trip detail (fase 2 skeleton): totals header, spese list (usually
/// empty until fase 3), FAB placeholder. Pops `true` after archive/delete
/// so the list screen reloads.
class TrasfertaDetailScreen extends StatefulWidget {
  const TrasfertaDetailScreen({
    super.key,
    required this.controller,
    required this.captureService,
    required this.orchestrator,
    required this.settingsService,
    required this.exchangeService,
  });

  final TrasfertaDetailController controller;
  final ReceiptCaptureService captureService;
  final RecognitionOrchestrator orchestrator;
  final SettingsService settingsService;
  final ExchangeService exchangeService;

  @override
  State<TrasfertaDetailScreen> createState() => _TrasfertaDetailScreenState();
}

class _TrasfertaDetailScreenState extends State<TrasfertaDetailScreen> {
  TrasfertaDetailController get controller => widget.controller;

  // Cached (not re-fetched per build, gotcha: a fresh Future in build would
  // rebuild forever) sheet defaults; loaded once, best-effort.
  OcrEngine _engineDefault = OcrEngine.mlkit;
  bool _claudeAvailable = false;

  @override
  void initState() {
    super.initState();
    controller.load();
    _loadOcrSettings();
  }

  Future<void> _loadOcrSettings() async {
    final engine = await widget.settingsService.ocrEngineDefault;
    final claudeAvailable = await widget.orchestrator.claudeAvailable;
    if (!mounted) return;
    setState(() {
      _engineDefault = engine;
      _claudeAvailable = claudeAvailable;
    });
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
    // Mutated by the "sheet-motore" row tap (StatefulBuilder below); read
    // again once the sheet is popped with 'scatta'.
    var selectedEngine = _engineDefault;
    final scelta = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
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
                key: const Key('sheet-motore'),
                leading: const Icon(Symbols.tune),
                title: Text('Motore: ${selectedEngine.label} ▾'),
                onTap: () async {
                  final picked = await _pickEngine(selectedEngine);
                  if (picked != null) {
                    setSheetState(() => selectedEngine = picked);
                  }
                },
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
      ),
    );
    if (!mounted) return;
    if (scelta == 'manuale') await _openSpesaForm();
    if (scelta == 'scatta') await _scattaEOcr(selectedEngine);
  }

  /// Per-shot engine choice (ML Kit / Claude); Claude disabled without a
  /// configured API key.
  Future<OcrEngine?> _pickEngine(OcrEngine current) {
    return showModalBottomSheet<OcrEngine>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('motore-mlkit'),
              title: const Text('ML Kit'),
              trailing: current == OcrEngine.mlkit
                  ? const Icon(Symbols.check)
                  : null,
              onTap: () => Navigator.of(context).pop(OcrEngine.mlkit),
            ),
            ListTile(
              key: const Key('motore-claude'),
              enabled: _claudeAvailable,
              title: const Text('Claude'),
              trailing: current == OcrEngine.claude
                  ? const Icon(Symbols.check)
                  : null,
              onTap: () => Navigator.of(context).pop(OcrEngine.claude),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  /// Scatta → progress fullscreen (annullabile) → form pre-compilato.
  /// Annullo: la foto resta nella cache temporanea del picker (non importata,
  /// non cancellata esplicitamente: la pulisce il SO), si torna al dettaglio.
  Future<void> _scattaEOcr(OcrEngine engine) async {
    final path = await _captureScatta();
    if (path == null || !mounted) return;
    final t = controller.trasferta;
    final result = await showOcrProgress(
      context,
      widget.orchestrator
          .recognize(path, engine: engine, linguaHint: t?.linguaDefault),
    );
    if (result == null || !mounted) return;
    _showFallbackSnackbarIfNeeded(result);
    _showCyrillicSnackbarIfNeeded(result, t);
    await _openSpesaForm(
      pendingFoto: path,
      parsed: result.receipt,
      onRetryOtherEngine: _makeRetryCallback(path, result.receipt.engine, t),
    );
  }

  /// "Riprova con altro motore" (banner OCR nel form): alterna l'ultimo
  /// motore usato per questa foto e ri-esegue il riconoscimento.
  Future<ParsedReceipt?> Function() _makeRetryCallback(
      String path, OcrEngine lastEngine, Trasferta? t) {
    var engine = lastEngine;
    return () async {
      engine = engine == OcrEngine.mlkit ? OcrEngine.claude : OcrEngine.mlkit;
      final result = await widget.orchestrator
          .recognize(path, engine: engine, linguaHint: t?.linguaDefault);
      // Realign to the ENGINE ACTUALLY USED (a claude→mlkit fallback returns
      // mlkit even though `engine` requested claude): the next toggle must
      // start from what was really shown, not from the request.
      engine = result.receipt.engine;
      if (!mounted) return null;
      _showFallbackSnackbarIfNeeded(result);
      _showCyrillicSnackbarIfNeeded(result, t);
      return result.receipt;
    };
  }

  void _showFallbackSnackbarIfNeeded(RecognitionResult result) {
    if (!result.claudeFallbackToMlkit) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Claude non raggiungibile, usato ML Kit')));
  }

  /// Gap noto ML Kit sul cirillico (spec): scontrino serbo non riconosciuto
  /// → suggerisce Claude se disponibile, altrimenti chiede la API key.
  void _showCyrillicSnackbarIfNeeded(RecognitionResult result, Trasferta? t) {
    if (!result.receipt.isEmpty || t?.linguaDefault != 'sr') return;
    final message = _claudeAvailable
        ? 'Testo in cirillico non riconosciuto — prova con il motore Claude'
        : 'Testo in cirillico non riconosciuto — configura una API key '
            'Claude nelle impostazioni per riconoscerlo';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _openSpesaForm({
    Spesa? spesa,
    String? pendingFoto,
    ParsedReceipt? parsed,
    Future<ParsedReceipt?> Function()? onRetryOtherEngine,
  }) async {
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
        parsed: parsed,
        onRetryOtherEngine: onRetryOtherEngine,
        exchange: widget.exchangeService,
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
                    if (controller.totaliPerCategoria.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CategoryTotals(
                        totali: controller.totaliPerCategoria,
                        valuta: controller.valutaCategorie,
                      ),
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
            for (final e in righeValuta(controller.totaliPerValuta,
                controller.trasferta?.valutaDefault ?? 'EUR'))
              Text(
                formatValuta(e.value, e.key),
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: amountFontFeatures,
                  fontWeight: FontWeight.w800,
                ),
              ),
            // The EUR line is a hint, not the total: hidden when there is
            // nothing converted (would read as a zeroed trip) and when EUR
            // is already the only currency shown above.
            if (controller.totaleEur > 0 && controller.valutaUnica != 'EUR')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '≈ ${formatEur(controller.totaleEur)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            if (controller.countSenzaEur > 0)
              Text(
                '${controller.countSenzaEur} spese senza conversione EUR',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-category totals (trip currency, or EUR when spese mix currencies)
/// with proportional bars (mockup "barre").
class _CategoryTotals extends StatelessWidget {
  const _CategoryTotals({required this.totali, required this.valuta});

  final Map<Categoria, double> totali;
  final String valuta;

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
            Text('Totali per categoria ($valuta)',
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
                      formatValuta(e.value, valuta),
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
