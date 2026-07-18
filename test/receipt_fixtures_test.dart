import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';

/// Fixture-based regression suite for [ReceiptParser.parse]: every
/// `<name>.txt` file under `test/fixtures/receipts/` is paired with a
/// `<name>.expected.json` describing the 5 fields the parser should
/// extract from it. The language hint passed to `parse` is the immediate
/// parent directory name (`it`, `en`, `ja`, `sr`, `de`); fixtures under
/// `edge/` are parsed with no hint (`linguaHint: null`) since they exercise
/// cross-language/no-signal edge cases rather than a single language.
///
/// NOTE (fixture aging): the parser's date plausibility window is relative
/// to the real wall clock (`DateTime.now()`) — `parse()` doesn't expose a
/// `now` override the way `extractDate` does. Fixture dates were chosen a
/// few months back from authoring time (2026-05..2026-07) so they stay
/// inside the 730-day window for a long time, but any fixed date
/// eventually ages out (~2 years after it). If this suite starts failing
/// ONLY on the `data` field many months from now, that's fixture decay,
/// not a parser regression: bump the dates in the affected `.txt` /
/// `.expected.json` pair to something recent and re-verify.
void main() {
  final fixturesDir = Directory('test/fixtures/receipts');

  final txtFiles = fixturesDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('fixture directory is not empty', () {
    expect(
      txtFiles,
      isNotEmpty,
      reason: 'no .txt fixtures found under ${fixturesDir.path}',
    );
  });

  for (final txtFile in txtFiles) {
    final normalizedPath = txtFile.path.replaceAll('\\', '/');
    final base = normalizedPath.substring(0, normalizedPath.length - 4);
    final name = base.split('/').last;
    final dirName = txtFile.parent.path.replaceAll('\\', '/').split('/').last;
    final jsonFile = File('$base.expected.json');

    test('fixture $dirName/$name', () {
      expect(
        jsonFile.existsSync(),
        true,
        reason: 'missing expected.json for ${txtFile.path}',
      );

      final text = txtFile.readAsStringSync();
      final expected =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final linguaHint = dirName == 'edge' ? null : dirName;

      final result = ReceiptParser().parse(text, linguaHint: linguaHint);

      final expectedImporto = (expected['importo'] as num?)?.toDouble();
      if (expectedImporto == null) {
        expect(result.importo, null, reason: 'importo');
      } else {
        expect(result.importo, isNotNull, reason: 'importo');
        expect(
          (result.importo! - expectedImporto).abs(),
          lessThan(0.001),
          reason: 'importo',
        );
      }

      expect(result.valuta, expected['valuta'], reason: 'valuta');

      final expectedDateStr = expected['data'] as String?;
      if (expectedDateStr == null) {
        expect(result.data, null, reason: 'data');
      } else {
        expect(result.data, isNotNull, reason: 'data');
        final actual = result.data!;
        final formatted = '${actual.year.toString().padLeft(4, '0')}-'
            '${actual.month.toString().padLeft(2, '0')}-'
            '${actual.day.toString().padLeft(2, '0')}';
        expect(formatted, expectedDateStr, reason: 'data');
      }

      expect(result.fornitore, expected['fornitore'], reason: 'fornitore');
      expect(result.lingua, expected['lingua'], reason: 'lingua');
    });
  }
}
