import 'package:flutter/material.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/trasferta.dart';

const _lingue = <String?, String>{
  null: 'Auto',
  'it': 'Italiano',
  'en': 'Inglese',
  'ja': 'Giapponese',
  'sr': 'Serbo',
  'de': 'Tedesco',
};

/// Create/edit trip form. [initial] == null → create; otherwise edit
/// (id, createdAt and archiviata are preserved).
class TrasfertaFormScreen extends StatefulWidget {
  const TrasfertaFormScreen({super.key, this.initial, required this.onSave});

  final Trasferta? initial;
  final Future<void> Function(Trasferta trasferta) onSave;

  @override
  State<TrasfertaFormScreen> createState() => _TrasfertaFormScreenState();
}

class _TrasfertaFormScreenState extends State<TrasfertaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome =
      TextEditingController(text: widget.initial?.nome ?? '');
  late final TextEditingController _luogo =
      TextEditingController(text: widget.initial?.luogo ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late DateTime _dataInizio = widget.initial?.dataInizio ?? DateTime.now();
  late DateTime? _dataFine = widget.initial?.dataFine;
  late String _valuta = widget.initial?.valutaDefault ?? 'EUR';
  late String? _lingua = widget.initial?.linguaDefault;

  @override
  void dispose() {
    _nome.dispose();
    _luogo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickData({required bool fine}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fine ? (_dataFine ?? _dataInizio) : _dataInizio,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (fine) {
        _dataFine = picked;
      } else {
        _dataInizio = picked;
      }
    });
  }

  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initial;
    final trasferta = Trasferta(
      id: initial?.id,
      nome: _nome.text.trim(),
      luogo: _luogo.text.trim().isEmpty ? null : _luogo.text.trim(),
      dataInizio: _dataInizio,
      dataFine: _dataFine,
      valutaDefault: _valuta,
      linguaDefault: _lingua,
      archiviata: initial?.archiviata ?? false,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: initial?.createdAt ?? DateTime.now(),
    );
    await widget.onSave(trasferta);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    // Frequent currencies first, then the rest (searchable picker → fase 3).
    final valute = [
      ...Currency.frequenti,
      ...Currency.values.where((c) => !c.frequente),
    ];

    return Scaffold(
      appBar: AppBar(
          title: Text(editing ? 'Modifica trasferta' : 'Nuova trasferta')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('campo-nome'),
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Inserisci un nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-luogo'),
              controller: _luogo,
              decoration: const InputDecoration(labelText: 'Luogo'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('campo-data-inizio'),
                    onPressed: () => _pickData(fine: false),
                    child: Text('Inizio: ${formatDate(_dataInizio)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('campo-data-fine'),
                    onPressed: () => _pickData(fine: true),
                    // Long-press clears the end date (trip in progress).
                    onLongPress: () => setState(() => _dataFine = null),
                    child: Text(_dataFine == null
                        ? 'Fine: —'
                        : 'Fine: ${formatDate(_dataFine!)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('campo-valuta'),
              initialValue: _valuta,
              decoration: const InputDecoration(labelText: 'Valuta default'),
              items: [
                for (final c in valute)
                  DropdownMenuItem(
                      value: c.code, child: Text('${c.code} — ${c.nome}')),
              ],
              onChanged: (v) => setState(() => _valuta = v ?? 'EUR'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('campo-lingua'),
              initialValue: _lingua,
              decoration:
                  const InputDecoration(labelText: 'Lingua default (hint OCR)'),
              items: [
                for (final e in _lingue.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _lingua = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salva,
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }
}
