import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/ocr/recognition_orchestrator.dart';

/// Fullscreen dark modal shown while [future] (an in-flight
/// [RecognitionOrchestrator.recognize] call) resolves.
///
/// Annulla pops immediately with `null` — the caller must discard the
/// pending photo — and the (still-running) [future]'s eventual completion is
/// then ignored. On success the dialog pops with the [RecognitionResult].
Future<RecognitionResult?> showOcrProgress(
  BuildContext context,
  Future<RecognitionResult> future,
) {
  return showDialog<RecognitionResult?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OcrProgressDialog(future: future),
  );
}

class _OcrProgressDialog extends StatefulWidget {
  const _OcrProgressDialog({required this.future});

  final Future<RecognitionResult> future;

  @override
  State<_OcrProgressDialog> createState() => _OcrProgressDialogState();
}

class _OcrProgressDialogState extends State<_OcrProgressDialog> {
  // Set on Annulla so a completion arriving afterwards (the future itself
  // keeps running — there is no cancellation on the OCR call) is ignored
  // instead of popping a second time.
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    widget.future.then((result) {
      if (_cancelled || !mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _annulla() {
    _cancelled = true;
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: AppColors.surfaceDark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 24),
              const Text(
                'Riconoscimento in corso…',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              TextButton(
                key: const Key('ocr-annulla'),
                onPressed: _annulla,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Annulla'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
