import 'claude_ocr_service.dart';
import 'ocr_service.dart';
import 'parsed_receipt.dart';
import 'receipt_parser.dart';

/// Outcome of [RecognitionOrchestrator.recognize]: the extracted fields plus
/// whether Claude was requested but unreachable and ML Kit was used instead.
class RecognitionResult {
  const RecognitionResult({
    required this.receipt,
    required this.claudeFallbackToMlkit,
  });

  final ParsedReceipt receipt;

  /// `true` → UI mostra SnackBar "Claude non raggiungibile, usato ML Kit".
  final bool claudeFallbackToMlkit;
}

/// Routes a receipt photo to the chosen OCR engine and never lets an
/// exception reach the UI: any Claude failure falls back to ML Kit, and any
/// ML Kit failure (direct or in the fallback path) yields an empty
/// [ParsedReceipt] rather than throwing.
class RecognitionOrchestrator {
  RecognitionOrchestrator({
    required this.mlkitOcr,
    required this.claudeOcr,
    required this.parser,
    required this.apiKeyProvider,
  });

  final OcrService mlkitOcr;
  final ClaudeOcrService claudeOcr;
  final ReceiptParser parser;
  final Future<String?> Function() apiKeyProvider;

  /// Whether a Claude API key is configured (present and non-empty).
  Future<bool> get claudeAvailable async {
    final key = await apiKeyProvider();
    return key != null && key.isNotEmpty;
  }

  Future<RecognitionResult> recognize(
    String imagePath, {
    required OcrEngine engine,
    String? linguaHint,
  }) async {
    if (engine == OcrEngine.claude) {
      try {
        final receipt = await claudeOcr.extract(imagePath, linguaHint: linguaHint);
        return RecognitionResult(receipt: receipt, claudeFallbackToMlkit: false);
      } catch (_) {
        return _recognizeWithMlkit(imagePath, linguaHint: linguaHint, fallback: true);
      }
    }
    return _recognizeWithMlkit(imagePath, linguaHint: linguaHint, fallback: false);
  }

  Future<RecognitionResult> _recognizeWithMlkit(
    String imagePath, {
    String? linguaHint,
    required bool fallback,
  }) async {
    try {
      final text = await mlkitOcr.recognizeText(imagePath);
      final receipt =
          parser.parse(text, linguaHint: linguaHint).copyWith(engine: OcrEngine.mlkit);
      return RecognitionResult(receipt: receipt, claudeFallbackToMlkit: fallback);
    } catch (_) {
      return RecognitionResult(
        receipt: const ParsedReceipt(engine: OcrEngine.mlkit, rawText: ''),
        claudeFallbackToMlkit: fallback,
      );
    }
  }
}
