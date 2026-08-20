import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';

import 'real_receipts_accuracy_test.dart' show isAcceptableVendor;

/// Accuracy harness on the SAME real Japanese receipts as
/// `real_receipts_accuracy_test.dart`, but with the human transcription
/// degraded by a model of ML Kit's own recognition errors before it reaches
/// the parser.
///
/// Why: the clean-transcription harness measures the parser on text no OCR
/// engine ever produces, so it saturates. Every degradation applied here is a
/// failure mode MEASURED on these very photos on a physical device (see the
/// repair functions in `receipt_parser.dart`, misure 2026-07-22), plus the
/// row-clustering errors `reconstructReadingOrder` can make when two printed
/// rows overlap vertically. Nothing here invents noise the engine has not
/// been observed to produce, and no digit is ever changed into another digit:
/// that would make the ground truth unrecoverable by any parser and would
/// measure the noise level instead of the algorithm.
///
/// The degradation is deterministic given a seed, and the suite scores every
/// receipt under [_seeds] different degradations of it, so the result cannot
/// be tuned to one lucky arrangement of merged rows: a change in the score is
/// always a change in the parser.
const double _accuracyTarget = 0.95;

/// Forty arbitrary but fixed degradations of every receipt: each seed places
/// the row merges, the full-width lines and the punctuation dust differently,
/// so a rule that only works on one lucky arrangement cannot reach the target.
final List<int> _seeds = List.generate(40, (i) => 1000 + i * 7919);

void main() {
  final dir = Directory('test/fixtures/real_receipts/jp');

  final txtFiles =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('real JP receipts, ML Kit noise: field accuracy >= '
      '${_accuracyTarget * 100}%', () {
    expect(txtFiles, isNotEmpty, reason: 'no real receipt fixtures found');

    var checks = 0;
    var hits = 0;
    final report = StringBuffer();

    for (final seed in _seeds) {
      for (final txtFile in txtFiles) {
        final path = txtFile.path.replaceAll('\\', '/');
        final name = '${path.split('/').last.replaceAll('.txt', '')}#$seed';
        final expected =
            jsonDecode(
                  File(
                    path.replaceAll('.txt', '.expected.json'),
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;

        final noisy = degradeLikeMlkit(txtFile.readAsStringSync(), seed: seed);
        final result = ReceiptParser().parse(noisy);

        final expectedImporto = (expected['importo'] as num).toDouble();
        final okImporto =
            result.importo != null &&
            (result.importo! - expectedImporto).abs() < 0.001;

        final actualDate = result.data == null
            ? null
            : '${result.data!.year.toString().padLeft(4, '0')}-'
                  '${result.data!.month.toString().padLeft(2, '0')}-'
                  '${result.data!.day.toString().padLeft(2, '0')}';
        final okData = actualDate == expected['data'];

        final okValuta = result.valuta == expected['valuta'];

        final accettabili = (expected['fornitore_accettabili'] as List)
            .cast<String>();
        final okFornitore = isAcceptableVendor(result.fornitore, accettabili);

        for (final ok in [okImporto, okData, okValuta, okFornitore]) {
          checks++;
          if (ok) hits++;
        }

        if (okImporto && okData && okValuta && okFornitore) continue;
        report.writeln(
          '$name  '
          'importo=${okImporto ? "OK" : "KO(${result.importo} != $expectedImporto)"}  '
          'data=${okData ? "OK" : "KO($actualDate != ${expected['data']})"}  '
          'valuta=${okValuta ? "OK" : "KO(${result.valuta})"}  '
          'fornitore=${okFornitore ? "OK" : "KO(${result.fornitore})"}  '
          'lingua=${result.lingua}',
        );
      }
    }

    final accuracy = hits / checks;
    // ignore: avoid_print
    print(
      '$report\nNOISY ACCURACY: $hits/$checks = '
      '${(accuracy * 100).toStringAsFixed(1)}%',
    );

    expect(
      accuracy,
      greaterThanOrEqualTo(_accuracyTarget),
      reason: 'field-level accuracy on degraded OCR below target\n$report',
    );
  });
}

final RegExp _katakana = RegExp(r'[ァ-ヺ]');
final RegExp _groupedAmount = RegExp(r'[¥￥](\d{1,3}(?:,\d{3})+)');
final RegExp _thousands = RegExp(r'(\d),(\d{3})');
final RegExp _kanaLongVowel = RegExp(r'(?<=[ァ-ヺ])ー(?=[ァ-ヺ])');
final RegExp _latinO = RegExp(r'(?<=[A-Za-z])O(?=[A-Za-z])');
final RegExp _latinOnly = RegExp(r'^[A-Za-z0-9·\-.\s+]+$');

/// Applies ML Kit's observed recognition errors to a clean transcription.
///
/// Systematic substitutions (the engine makes them every time it meets the
/// glyph) are applied to every occurrence; the layout-dependent ones are
/// applied to a deterministic subset drawn from [seed].
String degradeLikeMlkit(String text, {required int seed}) {
  final rnd = Random(seed);
  final lines = text.split('\n');
  final out = <String>[];

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];

    // 1. The `¥` glyph read as a `4` glued to the amount (`¥6,775` → `46,775`).
    line = line.replaceAllMapped(_groupedAmount, (m) => '4${m.group(1)}');

    // 2. Thousands group split after the comma (`¥1, 489`) — about half the
    //    time, as measured.
    if (rnd.nextBool()) {
      line = line.replaceAllMapped(
        _thousands,
        (m) => '${m.group(1)}, ${m.group(2)}',
      );
    }

    // 3. Katakana long vowel read as an ASCII hyphen (`ヨ-クベニマル`).
    line = line.replaceAll(_kanaLongVowel, '-');

    // 4. Latin O read as the CJK 口 (`LAWS口N`).
    line = line.replaceAll(_latinO, '口');

    // 5. 加 read as カ on the fixed card-slip label.
    line = line.replaceAll('加盟店', 'カ盟店');

    // 6. A latin-only logo line comes out garbled with a `#` (`HARD-oF#`).
    if (i == 0 && _latinOnly.hasMatch(line) && line.trim().isNotEmpty) {
      line = '${line.trim()}#';
    }

    // 7. Punctuation dust in front of a name line (`·健太鼓子`).
    if (i > 0 && i < 4 && rnd.nextInt(4) == 0 && line.trim().isNotEmpty) {
      line = '·${line.trim()}';
    }

    // 8. A stray latin letter from the logo glued to a katakana name.
    if (i > 0 && i < 4 && rnd.nextInt(5) == 0 && _katakana.hasMatch(line)) {
      line = 'K${line.trimLeft()}';
    }

    // 9. Full-width output, as on taxi/POS terminals.
    if (rnd.nextInt(6) == 0) line = _toFullWidth(line);

    out.add(line);
  }

  // 10. Row clustering merges two printed rows that overlap vertically.
  final merged = <String>[];
  for (var i = 0; i < out.length; i++) {
    if (i + 1 < out.length &&
        rnd.nextInt(9) == 0 &&
        out[i].trim().isNotEmpty &&
        out[i + 1].trim().isNotEmpty) {
      merged.add('${out[i].trim()} ${out[i + 1].trim()}');
      i++;
      continue;
    }
    merged.add(out[i]);
  }
  return merged.join('\n');
}

/// Half-width ASCII → full-width, ideographic space, `¥` → `￥`.
String _toFullWidth(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    if (rune >= 0x21 && rune <= 0x7E) {
      buffer.writeCharCode(rune + 0xFEE0);
    } else if (rune == 0x20) {
      buffer.writeCharCode(0x3000);
    } else if (rune == 0xA5) {
      buffer.writeCharCode(0xFFE5);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
