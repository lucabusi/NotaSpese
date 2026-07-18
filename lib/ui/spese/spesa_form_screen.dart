import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/currencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/foto.dart';
import '../../data/models/spesa.dart';
import '../../services/ocr/parsed_receipt.dart';
import '../foto/photo_viewer_screen.dart';
import '../shared/widgets/category_chips.dart';
import '../shared/widgets/currency_picker.dart';
import 'amount_input_controller.dart';
import 'amount_keypad.dart';

extension _OcrEngineLabel on OcrEngine {
  /// Banner-facing name (spec: "ML Kit" / "Claude").
  String get label => this == OcrEngine.claude ? 'Claude' : 'ML Kit';
}

/// Create/edit expense form. [initial] == null → create; otherwise edit
/// (id, createdAt, ocrEngine and tassoCambio are preserved). The amount is
/// typed only on the custom keypad, so the system keyboard never covers it
/// (spec UX). [onDelete] non-null → "Elimina spesa" with confirmation.
///
/// Photo handling stays in the caller: [onPickFoto] returns a captured
/// source path (scanner/camera/gallery), [photoPathResolver] turns the
/// relative paths of [initialFoto] into absolute ones; the chosen action
/// travels back through [onSave] (`nuovaFoto` / `rimuoviFoto`).
class SpesaFormScreen extends StatefulWidget {
  const SpesaFormScreen({
    super.key,
    required this.trasfertaId,
    required this.valutaDefault,
    this.initial,
    this.initialFoto,
    this.pendingFotoSourcePath,
    this.onPickFoto,
    this.photoPathResolver,
    required this.onSave,
    this.onDelete,
    this.parsed,
    this.onRetryOtherEngine,
  });

  final int trasfertaId;
  final String valutaDefault;
  final Spesa? initial;
  final Foto? initialFoto;

  /// Preset capture (📷 flow: photo taken before the form opens).
  final String? pendingFotoSourcePath;
  final Future<String?> Function()? onPickFoto;
  final Future<String> Function(String relative)? photoPathResolver;
  final Future<void> Function(Spesa spesa,
      {String? nuovaFoto, bool rimuoviFoto}) onSave;
  final Future<void> Function()? onDelete;

  /// OCR result from the receipt-capture flow (creation only). Drives the
  /// initial pre-fill and the confirmation banner.
  final ParsedReceipt? parsed;

  /// Re-runs recognition with the other engine (null → menu item hidden).
  final Future<ParsedReceipt?> Function()? onRetryOtherEngine;

  @override
  State<SpesaFormScreen> createState() => _SpesaFormScreenState();
}

class _SpesaFormScreenState extends State<SpesaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DateTime _today = DateTime.now();
  late String _valuta =
      widget.initial?.valuta ?? widget.parsed?.valuta ?? widget.valutaDefault;
  late final AmountInputController _importo = AmountInputController(
    decimalDigits: _decimalDigits(_valuta),
    initial: widget.initial != null
        ? AmountInputController.initialText(
            widget.initial!.importo, _decimalDigits(_valuta))
        : (widget.parsed?.importo == null
            ? ''
            : AmountInputController.initialText(
                widget.parsed!.importo!, _decimalDigits(_valuta))),
  );
  late final TextEditingController _importoEur = TextEditingController(
      text: widget.initial?.importoEur
              ?.toStringAsFixed(2)
              .replaceAll('.', ',') ??
          '');
  late Categoria _categoria = widget.initial?.categoria ?? Categoria.pranzo;
  late DateTime _data = widget.initial?.data ?? widget.parsed?.data ?? _today;
  late final TextEditingController _fornitore = TextEditingController(
      text: widget.initial?.fornitore ?? widget.parsed?.fornitore ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late String? _fotoSource = widget.pendingFotoSourcePath;
  bool _rimuoviFoto = false;
  // Current OCR result shown by the banner; updated wholesale on a
  // successful "riprova con altro motore" (engine + isEmpty variant).
  late ParsedReceipt? _currentParsed = widget.parsed;
  // Cached: a fresh Future per build would make FutureBuilder rebuild
  // forever (new future → setState → new build → new future).
  late final Future<String>? _thumbAbsolute = widget.initialFoto == null
      ? null
      : widget.photoPathResolver?.call(widget.initialFoto!.thumbPath);

  static int _decimalDigits(String code) =>
      Currency.fromCode(code)?.decimalDigits ?? 2;

  // Baseline values from the ORIGINAL parsed receipt (fixed, never updated
  // by a retry): "touched" means the current value diverged from these.
  String get _baseValuta => widget.parsed?.valuta ?? widget.valutaDefault;
  int get _baseDecimalDigits => _decimalDigits(_baseValuta);
  String get _baseImportoText => widget.parsed?.importo == null
      ? ''
      : AmountInputController.initialText(
          widget.parsed!.importo!, _baseDecimalDigits);
  DateTime get _baseData => widget.parsed?.data ?? _today;
  String get _baseFornitore => widget.parsed?.fornitore ?? '';

  bool get _valutaTouched =>
      widget.parsed != null && _valuta != _baseValuta;
  bool get _importoTouched =>
      widget.parsed != null && _importo.value != _baseImportoText;
  bool get _dataTouched => widget.parsed != null && _data != _baseData;
  bool get _fornitoreTouched =>
      widget.parsed != null && _fornitore.text != _baseFornitore;

  /// "Riprova con altro motore": overwrites only the fields the user has
  /// NOT touched since the original OCR pre-fill; always refreshes the
  /// banner (engine + isEmpty variant) on a non-null result.
  Future<void> _retryOtherEngine() async {
    final result = await widget.onRetryOtherEngine!.call();
    if (result == null || !mounted) return;
    setState(() {
      if (!_valutaTouched) {
        _valuta = result.valuta ?? widget.valutaDefault;
        _importo.decimalDigits = _decimalDigits(_valuta);
      }
      if (!_importoTouched) {
        _importo.value = result.importo == null
            ? ''
            : AmountInputController.initialText(
                result.importo!, _decimalDigits(_valuta));
      }
      if (!_dataTouched) {
        _data = result.data ?? _today;
      }
      if (!_fornitoreTouched) {
        _fornitore.text = result.fornitore ?? '';
      }
      _currentParsed = result;
    });
  }

  @override
  void dispose() {
    _importo.dispose();
    _importoEur.dispose();
    _fornitore.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickValuta() async {
    final picked =
        await CurrencyPickerScreen.show(context, selectedCode: _valuta);
    if (picked == null) return;
    setState(() {
      _valuta = picked.code;
      _importo.decimalDigits = picked.decimalDigits;
    });
  }

  Future<void> _pickData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _data = picked);
  }

  Future<void> _salva() async {
    final importo = _importo.amount;
    if (importo == null || importo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Inserisci un importo maggiore di zero')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final eurText = _importoEur.text.trim();
    // Spesa già in euro: l'importo convertito è sempre l'importo stesso
    // (il campo EUR manuale esiste solo per le valute estere).
    final importoEur = _valuta == 'EUR'
        ? importo
        : (eurText.isEmpty
            ? null
            : double.parse(eurText.replaceAll(',', '.')));

    final initial = widget.initial;
    final spesa = Spesa(
      id: initial?.id,
      trasfertaId: widget.trasfertaId,
      data: _data,
      categoria: _categoria,
      fornitore:
          _fornitore.text.trim().isEmpty ? null : _fornitore.text.trim(),
      importo: importo,
      valuta: _valuta,
      importoEur: importoEur,
      tassoCambio: initial?.tassoCambio,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ocrEngine: initial?.ocrEngine ?? widget.parsed?.engine.name,
      createdAt: initial?.createdAt ?? DateTime.now(),
    );
    await widget.onSave(spesa,
        nuovaFoto: _fotoSource, rimuoviFoto: _rimuoviFoto);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickFoto() async {
    final picked = await widget.onPickFoto?.call();
    if (picked == null) return;
    setState(() {
      _fotoSource = picked;
      _rimuoviFoto = false;
    });
  }

  Future<void> _openViewer(Foto foto) async {
    final resolver = widget.photoPathResolver;
    if (resolver == null) return;
    final absolute = await resolver(foto.filePath);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PhotoViewerScreen(
        imagePath: absolute,
        onDelete: () async => setState(() => _rimuoviFoto = true),
      ),
    ));
  }

  /// Pending capture → preview; existing photo → thumbnail (tap = viewer);
  /// none → dashed "Aggiungi foto" area (spec UX).
  Widget _fotoSection() {
    final source = _fotoSource;
    if (source != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: Image.file(
              File(source),
              key: const Key('foto-preview'),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Nuova foto allegata')),
          IconButton(
            key: const Key('foto-rimuovi'),
            icon: const Icon(Symbols.close),
            onPressed: () => setState(() => _fotoSource = null),
          ),
        ],
      );
    }
    final foto = widget.initialFoto;
    if (foto != null && !_rimuoviFoto) {
      return Row(
        children: [
          GestureDetector(
            key: const Key('foto-thumb'),
            onTap: () => _openViewer(foto),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: FutureBuilder<String>(
                future: _thumbAbsolute,
                builder: (context, snapshot) {
                  final path = snapshot.data;
                  if (path == null) {
                    return const SizedBox(width: 96, height: 96);
                  }
                  return Image.file(File(path),
                      width: 96, height: 96, fit: BoxFit.cover);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Foto scontrino')),
          IconButton(
            key: const Key('foto-rimuovi'),
            icon: const Icon(Symbols.delete),
            onPressed: () => setState(() => _rimuoviFoto = true),
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      key: const Key('foto-area-aggiungi'),
      onPressed: widget.onPickFoto == null ? null : _pickFoto,
      icon: const Icon(Symbols.add_a_photo),
      label: const Text('Aggiungi foto'),
    );
  }

  /// Success/warning banner above the amount (OCR pre-fill flow only).
  Widget? _ocrBanner() {
    final parsed = _currentParsed;
    if (parsed == null) return null;
    final isWarning = parsed.isEmpty;
    final fg = isWarning ? AppColors.warning : AppColors.success;
    final bg =
        isWarning ? AppColors.warningContainer : AppColors.successContainer;
    final text = isWarning
        ? 'Nessun dato riconosciuto — inserisci manualmente'
        : 'Compilato dallo scontrino (${parsed.engine.label}) · verifica i dati';
    return Container(
      key: const Key('ocr-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          Icon(isWarning ? Symbols.warning : Symbols.check_circle,
              color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
          if (widget.onRetryOtherEngine != null)
            PopupMenuButton<String>(
              key: const Key('ocr-riprova'),
              icon: Icon(Symbols.more_vert, color: fg),
              onSelected: (_) => _retryOtherEngine(),
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'retry',
                  child: Text('Riprova con altro motore'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _elimina() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la spesa?'),
        content: const Text('Verrà eliminata anche la foto, se presente.'),
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
    if (confirmed != true) return;
    await widget.onDelete!();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final textTheme = Theme.of(context).textTheme;
    final ocrBanner = _ocrBanner();

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Modifica spesa' : 'Nuova spesa')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (ocrBanner != null) ...[
              ocrBanner,
              const SizedBox(height: 12),
            ],
            ListenableBuilder(
              listenable: _importo,
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: Text(
                      _importo.value.isEmpty ? '0' : _importo.value,
                      key: const Key('display-importo'),
                      style: textTheme.displaySmall?.copyWith(
                        fontFeatures: amountFontFeatures,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('campo-valuta'),
                    onPressed: _pickValuta,
                    icon: const Icon(Symbols.expand_more),
                    label: Text(
                      _valuta,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            AmountKeypad(controller: _importo),
            const SizedBox(height: 12),
            // Per le spese già in EUR il controvalore è implicito.
            if (_valuta != 'EUR') ...[
              TextFormField(
                key: const Key('campo-importo-eur'),
                controller: _importoEur,
                decoration: const InputDecoration(
                    labelText: 'Importo EUR (opzionale)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return double.tryParse(t.replaceAll(',', '.')) == null
                      ? 'Importo non valido'
                      : null;
                },
              ),
              const SizedBox(height: 12),
            ],
            CategoryChips(
              selected: _categoria,
              onSelected: (c) => setState(() => _categoria = c),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('campo-data'),
              onPressed: _pickData,
              child: Text('Data: ${formatDate(_data)}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-fornitore'),
              controller: _fornitore,
              decoration: const InputDecoration(labelText: 'Fornitore'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('campo-note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _fotoSection(),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('salva-spesa'),
              onPressed: _salva,
              child: const Text('Salva'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('elimina-spesa'),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _elimina,
                child: const Text('Elimina spesa'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
