import 'package:flutter/material.dart';

import '../../services/ocr/parsed_receipt.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';

/// Full settings screen (fase 8), replacing ImpostazioniMinimal: OCR engine +
/// Claude API key, exchange rates, version. Photo options (Task 7) and
/// backup/restore (Task 8) are pending — not implemented yet, grafted onto
/// this screen in the next two tasks.
/// Services do the work and return results; every dialog and SnackBar lives
/// here.
///
/// The OCR section below consolidates what used to be two separate cards in
/// ImpostazioniMinimal ("Claude API key" + "Motore OCR predefinito") into one
/// "OCR" card, and relabels the API key field "Chiave API Claude Vision".
/// This is an intentional deviation from the "pure move" framing of Task 6 —
/// confirmed by the user on 2026-07-27 — not a leftover to reconcile. Do not
/// "restore" the old two-card layout.
class ImpostazioniScreen extends StatefulWidget {
  const ImpostazioniScreen({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
  });

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chiave API salvata.')));
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
          _sezioneOcr(context),
          const SizedBox(height: 16),
          _sezioneCambio(),
          const SizedBox(height: 16),
          Text(
            'Nota Spese v$appVersion',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _sezioneOcr(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OCR', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<OcrEngine>(
              key: const Key('motore-default'),
              segments: [
                const ButtonSegment(
                  value: OcrEngine.mlkit,
                  label: Text('ML Kit'),
                ),
                ButtonSegment(
                  value: OcrEngine.claude,
                  label: const Text('Claude'),
                  enabled: _configured,
                ),
              ],
              selected: {_engineDefault},
              onSelectionChanged: _onEngineChanged,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('campo-api-key'),
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Chiave API Claude Vision',
              ),
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
    );
  }

  Widget _sezioneCambio() {
    return Card(
      child: SwitchListTile(
        key: const Key('toggle-tassi-online'),
        title: const Text('Tassi di cambio online'),
        subtitle: const Text(
          'Conversione EUR automatica via frankfurter.app (tasso del giorno della spesa)',
        ),
        value: _tassiOnline,
        onChanged: _onTassiOnlineChanged,
      ),
    );
  }
}
