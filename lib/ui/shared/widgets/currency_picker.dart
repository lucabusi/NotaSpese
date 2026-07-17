import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/theme/app_theme.dart';

/// Fullscreen searchable currency picker (Specifiche.md §8): filter field,
/// frequent currencies on top. Pops the chosen [Currency], null on back.
class CurrencyPickerScreen extends StatefulWidget {
  const CurrencyPickerScreen({super.key, this.selectedCode});

  final String? selectedCode;

  static Future<Currency?> show(BuildContext context, {String? selectedCode}) =>
      Navigator.of(context).push<Currency>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CurrencyPickerScreen(selectedCode: selectedCode),
      ));

  @override
  State<CurrencyPickerScreen> createState() => _CurrencyPickerScreenState();
}

class _CurrencyPickerScreenState extends State<CurrencyPickerScreen> {
  String _query = '';

  Widget _tile(Currency c) => ListTile(
        key: Key('valuta-${c.code}'),
        leading: SizedBox(
          width: 44,
          child: Text(
            c.symbol,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        title: Text('${c.code} — ${c.nome}'),
        trailing: c.code == widget.selectedCode
            ? const Icon(Symbols.check, color: AppColors.primary)
            : null,
        onTap: () => Navigator.of(context).pop(c),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtrate = q.isEmpty
        ? const <Currency>[]
        : Currency.values
            .where((c) =>
                c.code.toLowerCase().contains(q) ||
                c.nome.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Valuta')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('filtro-valuta'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.search),
                hintText: 'Cerca per codice o nome',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: q.isNotEmpty
                ? ListView(children: [for (final c in filtrate) _tile(c)])
                : ListView(
                    children: [
                      const _SectionHeader('Frequenti'),
                      for (final c in Currency.frequenti) _tile(c),
                      const Divider(),
                      const _SectionHeader('Tutte le valute'),
                      for (final c
                          in Currency.values.where((c) => !c.frequente))
                        _tile(c),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textTertiary, letterSpacing: 1),
          ),
        ),
      );
}
