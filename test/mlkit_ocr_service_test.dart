import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';

/// Only the script choice is host-testable: `TextRecognizer` itself is a
/// native plugin (cf. the note in MlkitOcrService).
void main() {
  test('lingua ja selects the japanese recognizer', () {
    expect(MlkitOcrService.scriptFor('ja'), TextRecognitionScript.japanese);
  });

  test('other languages and auto (null) stay on latin', () {
    expect(MlkitOcrService.scriptFor('it'), TextRecognitionScript.latin);
    expect(MlkitOcrService.scriptFor('en'), TextRecognitionScript.latin);
    expect(MlkitOcrService.scriptFor('sr'), TextRecognitionScript.latin);
    // Polish is latin-script: the diacritics (ł, ą, ę, ż) come from the same
    // ML Kit latin model, so there is nothing to switch.
    expect(MlkitOcrService.scriptFor('pl'), TextRecognitionScript.latin);
    expect(MlkitOcrService.scriptFor(null), TextRecognitionScript.latin);
  });
}
