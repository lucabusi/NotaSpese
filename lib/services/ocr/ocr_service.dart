/// Text recognition backend abstraction (ML Kit on-device, or a future
/// cloud engine), decoupled from the parsing logic in later tasks.
abstract class OcrService {
  /// Raw recognized text, lines separated by `\n`. [linguaHint] è la lingua
  /// della trasferta (`Trasferta.linguaDefault`): i motori che hanno modelli
  /// per script la usano per scegliere il riconoscitore.
  Future<String> recognizeText(String imagePath, {String? linguaHint});
}
