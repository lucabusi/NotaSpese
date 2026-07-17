import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/spesa.dart';
import 'trasferta_detail_controller.dart';
import 'trasferta_form_screen.dart';

enum DetailAction { modifica, archivia, ripristina, elimina }

/// Trip detail (fase 2 skeleton): totals header, spese list (usually
/// empty until fase 3), FAB placeholder. Pops `true` after archive/delete
/// so the list screen reloads.
class TrasfertaDetailScreen extends StatefulWidget {
  const TrasfertaDetailScreen({super.key, required this.controller});

  final TrasfertaDetailController controller;

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
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Inserimento spese: fase 3')),
            ),
            child: const Icon(Symbols.add),
          ),
          body: controller.loading && t == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TotalsHeader(controller: controller),
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
                        for (final spesa in entry.value) _SpesaTile(spesa),
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

class _SpesaTile extends StatelessWidget {
  const _SpesaTile(this.spesa);

  final Spesa spesa;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(spesa.categoria.icon, color: AppColors.primary),
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
