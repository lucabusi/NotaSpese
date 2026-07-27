import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/ocr/parsed_receipt.dart';
import '../../services/photo/photo_dir_migration.dart';
import '../../services/photo/photo_dir_usage.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';

/// Full settings screen (fase 8), replacing ImpostazioniMinimal: OCR engine +
/// Claude API key, photo options, exchange rates, version. Backup/restore
/// (Task 8) is pending — not implemented yet, grafted onto this screen in the
/// next task.
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
    required this.photoDirFor,
    this.migrationService = const PhotoDirMigrationService(),
  });

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  /// Resolves the absolute photo dir of a [PhotoDirKind] (wired to main.dart);
  /// needed to migrate between the two and to measure disk usage.
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
  final PhotoDirMigrationService migrationService;

  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
  final _apiKeyController = TextEditingController();
  bool _configured = false;
  OcrEngine _engineDefault = OcrEngine.mlkit;
  bool _tassiOnline = true;
  int _jpgQuality = SettingsService.defaultJpgQuality;
  PhotoDirKind _dirKind = PhotoDirKind.internal;
  PhotoDirUsage _usage = PhotoDirUsage.empty;
  bool _migrating = false;

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
    final quality = await widget.settingsService.jpgQuality;
    final dirKind = await widget.settingsService.photoDirKind;
    if (!mounted) return;
    setState(() {
      _configured = key != null && key.isNotEmpty;
      _engineDefault = engine;
      _tassiOnline = tassi;
      _jpgQuality = quality;
      _dirKind = dirKind;
    });
    await _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final usage = await PhotoDirUsage.measure(
      await widget.photoDirFor(_dirKind),
    );
    if (!mounted) return;
    setState(() => _usage = usage);
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

  Future<void> _onQualityChanged(double value) async {
    final quality = value.round();
    setState(() => _jpgQuality = quality);
    await widget.settingsService.setJpgQuality(quality);
  }

  /// The `foto` table stores paths relative to the photo base dir, so
  /// switching dir without moving the files would hide every existing photo:
  /// the change is only applied together with the migration (spec fase 8,
  /// amended 2026-07-25) — hence "Migra ora" or nothing.
  Future<void> _onDirKindChanged(Set<PhotoDirKind> selection) async {
    final target = selection.first;
    if (target == _dirKind || _migrating) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('dialog-migrazione'),
            title: const Text('Spostare le foto?'),
            content: const Text(
              'Le foto già salvate vengono spostate nella nuova cartella. '
              'Senza spostarle non sarebbero più visibili nell\'app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const Key('conferma-migrazione'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Migra ora'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _migrating = true);
    final from = await widget.photoDirFor(_dirKind);
    final to = await widget.photoDirFor(target);
    final result = await widget.migrationService.migrate(from: from, to: to);
    if (!mounted) return;
    if (result.ok) {
      await widget.settingsService.setPhotoDirKind(target);
      if (!mounted) return;
      setState(() {
        _dirKind = target;
        _migrating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.movedFiles == 1
                ? '1 foto spostata.'
                : '${result.movedFiles} foto spostate.',
          ),
        ),
      );
      await _refreshUsage();
    } else {
      setState(() => _migrating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
    }
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
          _sezioneFoto(context),
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

  Widget _sezioneFoto(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Foto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Qualità JPG: $_jpgQuality%'),
            Slider(
              key: const Key('slider-qualita-jpg'),
              min: SettingsService.minJpgQuality.toDouble(),
              max: SettingsService.maxJpgQuality.toDouble(),
              divisions:
                  SettingsService.maxJpgQuality - SettingsService.minJpgQuality,
              label: '$_jpgQuality%',
              value: _jpgQuality.toDouble(),
              onChanged: _onQualityChanged,
            ),
            const Text('Vale per le nuove foto.'),
            const SizedBox(height: 16),
            const Text('Cartella foto'),
            const SizedBox(height: 8),
            SegmentedButton<PhotoDirKind>(
              key: const Key('selettore-dir-foto'),
              segments: const [
                ButtonSegment(
                  value: PhotoDirKind.internal,
                  label: Text('Interna'),
                ),
                ButtonSegment(
                  value: PhotoDirKind.external,
                  label: Text('Esterna'),
                ),
              ],
              selected: {_dirKind},
              onSelectionChanged: _migrating ? null : _onDirKindChanged,
            ),
            const SizedBox(height: 16),
            Row(
              key: const Key('spazio-usato'),
              children: [
                Expanded(child: Text('Spazio usato: ${_usage.label}')),
                IconButton(
                  key: const Key('refresh-spazio'),
                  onPressed: _refreshUsage,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Ricalcola',
                ),
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
