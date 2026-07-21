import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../trasferte/trasferte_list_controller.dart';
import '../currency_rows.dart';

enum TripCardAction { archivia, ripristina, elimina }

/// Trip list card (mockup: icona, nome, date, badge valuta, n. spese, totale).
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.item,
    this.onTap,
    this.onArchivia,
    this.onRipristina,
    this.onElimina,
  });

  final TrasfertaListItem item;
  final VoidCallback? onTap;
  final VoidCallback? onArchivia;
  final VoidCallback? onRipristina;
  final VoidCallback? onElimina;

  void _onAction(TripCardAction action) {
    switch (action) {
      case TripCardAction.archivia:
        onArchivia?.call();
      case TripCardAction.ripristina:
        onRipristina?.call();
      case TripCardAction.elimina:
        onElimina?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = item.trasferta;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [
      if (t.luogo != null && t.luogo!.isNotEmpty) t.luogo,
      formatDateRange(t.dataInizio, t.dataFine),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.primary,
                child: Icon(Symbols.flight_takeoff),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.nome,
                              style: textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        _Badge(text: t.valutaDefault),
                        if (t.archiviata) ...[
                          const SizedBox(width: 6),
                          const _Badge(
                            text: 'ARCHIVIATA',
                            background: AppColors.archivioContainer,
                            foreground: AppColors.archivio,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text('${item.numSpese} spese',
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in righeValuta(
                      item.totaliPerValuta, item.trasferta.valutaDefault))
                    Text(
                      formatValuta(e.value, e.key),
                      style: textTheme.titleMedium?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  // Same rule as the detail header: the EUR hint disappears
                  // when nothing is converted or when EUR is already shown.
                  if (item.totaleEur > 0 &&
                      !(item.totaliPerValuta.length == 1 &&
                          item.totaliPerValuta.containsKey('EUR')))
                    Text(
                      '≈ ${formatEur(item.totaleEur)}',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
              PopupMenuButton<TripCardAction>(
                onSelected: _onAction,
                itemBuilder: (context) => [
                  if (t.archiviata)
                    const PopupMenuItem(
                        value: TripCardAction.ripristina,
                        child: Text('Ripristina'))
                  else
                    const PopupMenuItem(
                        value: TripCardAction.archivia,
                        child: Text('Archivia')),
                  const PopupMenuItem(
                      value: TripCardAction.elimina, child: Text('Elimina')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    this.background = AppColors.primaryContainer,
    this.foreground = AppColors.primary,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}
