import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_service.dart';

/// ML Kit wrapper for on-device OCR. Native plugin (no host test isolation).
///
/// [NON-BLOCKING]: `script: TextRecognitionScript.latin` — handles Latin scripts.
/// Japanese would require `TextRecognitionScript.japanese` (extra model).
/// Decision point at first device test: if JA text returns empty, instantiate
/// recognizer per trip-hint language. Not verifiable on host (cf. `ReceiptCaptureService`);
/// verify at first device build.
class MlkitOcrService implements OcrService {
  @override
  Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text; // rows already \n-separated
    } finally {
      await recognizer.close();
    }
  }
}
