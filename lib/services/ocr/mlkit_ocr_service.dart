import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_layout.dart';
import 'ocr_service.dart';

/// ML Kit wrapper for on-device OCR. Native plugin (no host test isolation).
///
/// [FIX] Decision point risolto al primo test su dispositivo: con
/// `TextRecognitionScript.latin` gli scontrini giapponesi tornavano vuoti.
/// Il riconoscitore viene scelto dalla lingua della trasferta; il modello
/// japanese include comunque i caratteri latini, quindi importi e date
/// restano leggibili.
class MlkitOcrService implements OcrService {
  /// `linguaHint` = `Trasferta.linguaDefault` (`it|en|ja|sr|de|pl`, NULL = auto).
  /// Solo il giapponese ha un modello dedicato tra le lingue supportate: il
  /// serbo cirillico non è coperto da ML Kit v2 (resta sul percorso Claude).
  static TextRecognitionScript scriptFor(String? linguaHint) =>
      linguaHint == 'ja'
          ? TextRecognitionScript.japanese
          : TextRecognitionScript.latin;

  @override
  Future<String> recognizeText(String imagePath, {String? linguaHint}) async {
    final recognizer = TextRecognizer(script: scriptFor(linguaHint));
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      // [FIX] ML Kit returns receipt text by COLUMN (labels apart from their
      // amounts): rebuild the visual reading order from the line bounding
      // boxes instead of trusting result.text (misura 2026-07-22: importo
      // 0/14 senza geometria).
      final lines = <OcrLine>[
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrLine(
              text: line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
      ];
      return lines.isEmpty ? result.text : reconstructReadingOrder(lines);
    } finally {
      await recognizer.close();
    }
  }
}
