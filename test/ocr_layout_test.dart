import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/ocr_layout.dart';

OcrLine line(String text, double left, double top,
        {double width = 100, double height = 20}) =>
    OcrLine(
      text: text,
      left: left,
      top: top,
      right: left + width,
      bottom: top + height,
    );

void main() {
  group('reconstructReadingOrder', () {
    test('empty input gives empty string', () {
      expect(reconstructReadingOrder(const []), '');
    });

    test('single column stays in top-to-bottom order', () {
      final lines = [
        line('riga2', 0, 40),
        line('riga1', 0, 0),
        line('riga3', 0, 80),
      ];
      expect(reconstructReadingOrder(lines), 'riga1\nriga2\nriga3');
    });

    test('two columns delivered column-wise get interlaced by row', () {
      // ML Kit order: whole label column first, then the amount column.
      final lines = [
        line('小計', 0, 0),
        line('消費税', 0, 40),
        line('合計', 0, 80),
        line('¥1,000', 200, 0),
        line('¥100', 200, 40),
        line('¥1,100', 200, 80),
      ];
      expect(
        reconstructReadingOrder(lines),
        '小計 ¥1,000\n消費税 ¥100\n合計 ¥1,100',
      );
    });

    test('same row is sorted left-to-right regardless of input order', () {
      final lines = [
        line('¥500', 200, 0),
        line('合計', 0, 0),
      ];
      expect(reconstructReadingOrder(lines), '合計 ¥500');
    });

    test('slight vertical offset still merges into one row', () {
      // Centers 8px apart with 20px-high lines: same visual row.
      final lines = [
        line('合計', 0, 0),
        line('¥500', 200, 8),
      ];
      expect(reconstructReadingOrder(lines), '合計 ¥500');
    });

    test('rows with no vertical overlap stay separate', () {
      final lines = [
        line('合計', 0, 0),
        line('¥500', 200, 30),
      ];
      expect(reconstructReadingOrder(lines), '合計\n¥500');
    });

    test('taller line absorbs a short line whose center it spans', () {
      // A tall kanji line (height 30) next to a small digit line (height 14).
      final lines = [
        line('お預り', 0, 0, height: 30),
        line('¥2,000', 200, 10, height: 14),
      ];
      expect(reconstructReadingOrder(lines), 'お預り ¥2,000');
    });
  });
}
