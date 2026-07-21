import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/lingua_hint.dart';

/// [effectiveLinguaHint] decides which OCR language hint actually reaches
/// the OCR service: an explicit `linguaDefault` always wins; when absent,
/// infer from the trip's currency so old JPY trips (created before
/// `linguaDefault` existed) still get the japanese recognizer.
void main() {
  test('explicit lingua wins over currency inference', () {
    expect(effectiveLinguaHint('it', 'JPY'), 'it');
  });

  test('null lingua + JPY currency infers ja', () {
    expect(effectiveLinguaHint(null, 'JPY'), 'ja');
  });

  test('null lingua + EUR currency stays null (auto)', () {
    expect(effectiveLinguaHint(null, 'EUR'), isNull);
  });

  test('null lingua + null currency stays null (auto)', () {
    expect(effectiveLinguaHint(null, null), isNull);
  });
}
