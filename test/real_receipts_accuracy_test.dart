import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';

/// Accuracy harness on REAL Japanese receipts (`scontrini_training/`),
/// transcribed line-by-line into `test/fixtures/real_receipts/jp/*.txt`
/// with the human ground truth in the paired `*.expected.json`.
///
/// Unlike `receipt_fixtures_test.dart` (per-fixture pass/fail regression on
/// synthetic receipts), this suite scores 4 fields per receipt
/// (importo/data/valuta/fornitore) and asserts an overall field-level
/// accuracy target, because a few misses on genuinely ambiguous real-world
/// layouts are acceptable while a regression in the aggregate is not.
///
/// `fornitore` is scored against a LIST of acceptable renderings
/// (`fornitore_accettabili`): on a real receipt the brand line, the branch
/// line and the legal entity are all defensible vendor names for an expense.
///
/// No `linguaHint` is passed on purpose: the parser must recover the
/// language from the text alone, as it does when the trip language is unset.
const double _accuracyTarget = 0.80;

void main() {
  final dir = Directory('test/fixtures/real_receipts/jp');

  final txtFiles = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('real JP receipts: field accuracy >= ${_accuracyTarget * 100}%', () {
    expect(txtFiles, isNotEmpty, reason: 'no real receipt fixtures found');

    var checks = 0;
    var hits = 0;
    final report = StringBuffer();

    for (final txtFile in txtFiles) {
      final path = txtFile.path.replaceAll('\\', '/');
      final name = path.split('/').last.replaceAll('.txt', '');
      final expected = jsonDecode(
        File(path.replaceAll('.txt', '.expected.json')).readAsStringSync(),
      ) as Map<String, dynamic>;

      final result = ReceiptParser().parse(txtFile.readAsStringSync());

      final expectedImporto = (expected['importo'] as num).toDouble();
      final okImporto = result.importo != null &&
          (result.importo! - expectedImporto).abs() < 0.001;

      final actualDate = result.data == null
          ? null
          : '${result.data!.year.toString().padLeft(4, '0')}-'
              '${result.data!.month.toString().padLeft(2, '0')}-'
              '${result.data!.day.toString().padLeft(2, '0')}';
      final okData = actualDate == expected['data'];

      final okValuta = result.valuta == expected['valuta'];

      final accettabili =
          (expected['fornitore_accettabili'] as List).cast<String>();
      final okFornitore =
          result.fornitore != null && accettabili.contains(result.fornitore);

      for (final ok in [okImporto, okData, okValuta, okFornitore]) {
        checks++;
        if (ok) hits++;
      }

      report.writeln(
        '$name  '
        'importo=${okImporto ? "OK" : "KO(${result.importo} != $expectedImporto)"}  '
        'data=${okData ? "OK" : "KO($actualDate != ${expected['data']})"}  '
        'valuta=${okValuta ? "OK" : "KO(${result.valuta})"}  '
        'fornitore=${okFornitore ? "OK" : "KO(${result.fornitore})"}  '
        'lingua=${result.lingua}',
      );
    }

    final accuracy = hits / checks;
    // ignore: avoid_print
    print('$report\nACCURACY: $hits/$checks = '
        '${(accuracy * 100).toStringAsFixed(1)}%');

    expect(
      accuracy,
      greaterThanOrEqualTo(_accuracyTarget),
      reason: 'field-level accuracy below target\n$report',
    );
  });
}
