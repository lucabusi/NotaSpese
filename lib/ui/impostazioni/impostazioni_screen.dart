import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup/backup_service.dart';
import '../../services/ocr/parsed_receipt.dart';
import '../../services/photo/photo_dir_migration.dart';
import '../../services/photo/photo_dir_usage.dart';
import '../../services/settings/api_key_store.dart';
import '../../services/settings/settings_service.dart';
import '../../version.dart';

/// Full settings screen (fase 8), replacing ImpostazioniMinimal: OCR engine +
/// Claude API key, photo options, exchange rates, backup/restore, version.
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
  ImpostazioniScreen({
    super.key,
    required this.apiKeyStore,
    required this.settingsService,
    required this.photoDirFor,
    required this.backupService,
    this.migrationService = const PhotoDirMigrationService(),
    Future<XFile?> Function()? pickZip,
    Future<void> Function(XFile)? shareFile,
  })  : pickZip = pickZip ?? _pickZipFile,
        shareFile = shareFile ??
            ((file) => SharePlus.instance.share(ShareParams(files: [file])));

  final ApiKeyStore apiKeyStore;
  final SettingsService settingsService;

  /// Resolves the absolute photo dir of a [PhotoDirKind] (wired to main.dart);
  /// needed to migrate between the two and to measure disk usage.
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
  final BackupService backupService;
  final PhotoDirMigrationService migrationService;

  /// Injected so the backup/restore flow is host-testable: the real
  /// implementations are platform channels (pattern: ExportService).
  final Future<XFile?> Function() pickZip;
  final Future<void> Function(XFile) shareFile;

  static Future<XFile?> _pickZipFile() => openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
              label: 'Backup zip',
              extensions: ['zip'],
              mimeTypes: ['application/zip']),
        ],
      );

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
  // Backup/restore and the photo-dir migration both move files under the
  // photo dir and swap the DB file: guarded by the same "is something
  // in-flight" idea so the two can never race each other, not just their own
  // repeat taps (see _backupOra/_ripristinaBackup and _onDirKindChanged).
  // Spans the *whole* flow, tap to completion — including the file-picker and
  // confirmation-dialog awaits, not just the actual createBackup/restoreBackup
  // call, so a second tap on either button during those awaits cannot start a
  // second, racing backup/restore.
  bool _backupRunning = false;
  // Narrower than _backupRunning: true only while createBackup()/
  // restoreBackup() itself is in flight. Drives the progress bar. Tying the
  // bar to _backupRunning instead would animate it indefinitely while the
  // native file picker or the confirmation AlertDialog is merely waiting on
  // the user — misleading (nothing is "working" yet) and, in the widget
  // tests, an indeterminate animation that never settles hangs
  // pumpAndSettle.
  bool _backupWorking = false;

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
    final PhotoDirUsage usage;
    try {
      usage = await PhotoDirUsage.measure(await widget.photoDirFor(_dirKind));
    } on Exception {
      // [NON-BLOCKING] a file vanishing between the listing and its stat, or
      // an unavailable dir, must not abort the caller: _load() would leave the
      // whole screen unpopulated. Keep the last known figure.
      return;
    }
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

  void _onQualityChanging(double value) =>
      setState(() => _jpgQuality = value.round());

  /// Persisted on drag end only: [Slider.onChanged] fires on every tick (40
  /// divisions), which would hit SharedPreferences dozens of times per drag
  /// for the same final value. The label still follows the thumb live.
  Future<void> _onQualityChanged(double value) =>
      widget.settingsService.setJpgQuality(value.round());

  /// The `foto` table stores paths relative to the photo base dir, so
  /// switching dir without moving the files would hide every existing photo:
  /// the change is only applied together with the migration (spec fase 8,
  /// amended 2026-07-25) — hence "Migra ora" or nothing.
  Future<void> _onDirKindChanged(Set<PhotoDirKind> selection) async {
    final target = selection.first;
    if (target == _dirKind || _migrating || _backupRunning) return;

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
    try {
      final from = await widget.photoDirFor(_dirKind);
      final to = await widget.photoDirFor(target);
      final result = await widget.migrationService.migrate(from: from, to: to);
      if (!mounted) return;
      if (result.ok) {
        await widget.settingsService.setPhotoDirKind(target);
        if (!mounted) return;
        setState(() => _dirKind = target);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_esitoSpostamento(result))));
        await _refreshUsage();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error!)));
      }
    } on Exception {
      // Neither photoDirFor (MissingPlatformDirectoryException) nor
      // PhotoDirMigrationService (its source listing sits outside its own try)
      // is exception-total. Without this the screen would keep _migrating at
      // true forever and, since it lives in HomeShell's IndexedStack and is
      // never rebuilt from scratch, the selector would stay dead for the rest
      // of the session. The move is abandoned before any delete, so the photos
      // are still in the previous dir and the setting has not changed.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Spostamento non riuscito: le foto sono rimaste nella cartella precedente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  /// 0 files is not an error: internal and external resolve to the same dir
  /// when getExternalStorageDirectory() is unavailable (main.dart), and
  /// "0 foto spostate." would read as a failure.
  String _esitoSpostamento(MigrationResult result) =>
      switch (result.movedFiles) {
        0 => 'Nessuna foto da spostare.',
        1 => '1 foto spostata.',
        final moved => '$moved foto spostate.',
      };

  Future<void> _onTassiOnlineChanged(bool value) async {
    await widget.settingsService.setTassiOnline(value);
    if (!mounted) return;
    setState(() => _tassiOnline = value);
  }

  Future<void> _backupOra() async {
    if (_backupRunning || _migrating) return;
    setState(() {
      _backupRunning = true;
      _backupWorking = true;
    });
    try {
      final zip = await widget.backupService.createBackup();
      await widget.shareFile(XFile(zip.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup non riuscito.')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _backupRunning = false;
          _backupWorking = false;
        });
      }
    }
  }

  Future<void> _ripristinaBackup() async {
    // Guarded (and _backupRunning set) *before* the picker await, not after:
    // the native file-picker dialog can stay open for a while, and until this
    // returns a second tap on "Backup ora" would run createBackup() (which
    // does not close the DB) concurrently with a later restoreBackup() swap —
    // a real race, not just a double-tap on this same button.
    if (_backupRunning || _migrating) return;
    setState(() => _backupRunning = true);
    final picked = await widget.pickZip();
    if (picked == null) {
      if (mounted) setState(() => _backupRunning = false);
      return;
    }
    if (!mounted) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('dialog-conferma-restore'),
            title: const Text('Ripristinare il backup?'),
            content: const Text(
              'Il ripristino sovrascrive i dati attuali (trasferte, spese e '
              'foto). L\'operazione non è annullabile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const Key('conferma-restore'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ripristina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      if (mounted) setState(() => _backupRunning = false);
      return;
    }
    if (!mounted) return;

    setState(() => _backupWorking = true);
    final result =
        await widget.backupService.restoreBackup(File(picked.path));
    if (!mounted) return;
    setState(() {
      _backupRunning = false;
      _backupWorking = false;
    });
    if (!result.ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    // No RestartWidget in v1.0 (spec decision 4): the DB connection is closed
    // and the in-memory controllers are stale, so ask for a restart.
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('dialog-riavvia'),
        title: const Text('Backup ripristinato'),
        content: const Text(
          'Chiudi e riavvia l\'app per vedere i dati ripristinati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
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
          _sezioneBackup(context),
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
              onChanged: _onQualityChanging,
              onChangeEnd: _onQualityChanged,
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
              onSelectionChanged:
                  (_migrating || _backupRunning) ? null : _onDirKindChanged,
            ),
            const SizedBox(height: 16),
            Row(
              key: const Key('spazio-usato'),
              children: [
                Expanded(child: Text('Spazio usato: ${_usage.label}')),
                IconButton(
                  key: const Key('refresh-spazio'),
                  // Measuring a dir that a migration or a restore is
                  // emptying/swapping would race it, and its setState could
                  // land after that operation's.
                  onPressed:
                      (_migrating || _backupRunning) ? null : _refreshUsage,
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

  Widget _sezioneBackup(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Un unico file zip con database e foto, da condividere o '
              'salvare dove vuoi.',
            ),
            const SizedBox(height: 8),
            if (_backupWorking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            Row(
              children: [
                ElevatedButton(
                  key: const Key('backup-ora'),
                  onPressed:
                      (_backupRunning || _migrating) ? null : _backupOra,
                  child: const Text('Backup ora'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('ripristina-backup'),
                  onPressed: (_backupRunning || _migrating)
                      ? null
                      : _ripristinaBackup,
                  child: const Text('Ripristina da backup'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
