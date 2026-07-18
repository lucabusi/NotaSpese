/// Text recognition backend abstraction (ML Kit on-device, or a future
/// cloud engine), decoupled from the parsing logic in later tasks.
abstract class OcrService {
  /// Raw recognized text, lines separated by `\n`.
  Future<String> recognizeText(String imagePath);
}
