import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nota_spese/services/ocr/mlkit_ocr_service.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:path_provider/path_provider.dart';

/// ML Kit OCR accuracy harness — runs ON A PHYSICAL ANDROID DEVICE.
///
/// Unlike `test/real_receipts_accuracy_test.dart` (which feeds the parser a
/// HUMAN transcription of the photos), this suite runs the real
/// `MlkitOcrService` on the 53 photos in `scontrini_training/` (bundled as
/// assets, see the [OCR-HARNESS] block in pubspec.yaml) and measures:
///
/// 1. OCR text accuracy: 1 - CER (character error rate, Levenshtein) against
///    the human transcription in `test/fixtures/real_receipts/jp/*.txt`,
///    after whitespace normalization;
/// 2. end-to-end field accuracy: `ReceiptParser` on the ML Kit text scored
///    against `*.expected.json` (same 4 fields / same rules as the host
///    harness: importo, data, valuta, fornitore su lista accettabili).
///
/// The full recognized text of every receipt is printed between
/// `--- OCR <name> BEGIN/END ---` markers so it can be captured from the
/// console.
///
/// Run (device connected, USB debugging on):
///   `flutter test integration_test/mlkit_ocr_accuracy_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ML Kit OCR accuracy on real JP receipts', (tester) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final images = manifest
        .listAssets()
        .where((a) => a.startsWith('scontrini_training/') && a.endsWith('.jpg'))
        .toList()
      ..sort();
    expect(images, isNotEmpty, reason: 'no receipt photos bundled as assets');

    final tmpDir = await getTemporaryDirectory();
    final ocr = MlkitOcrService();

    var fieldChecks = 0;
    var fieldHits = 0;
    var charAccSum = 0.0;
    final report = StringBuffer();

    for (final asset in images) {
      final name = asset.split('/').last.replaceAll('.jpg', '');

      // Photo asset -> temp file (ML Kit wants a file path).
      final bytes = await rootBundle.load(asset);
      final imgFile = File('${tmpDir.path}/$name.jpg')
        ..writeAsBytesSync(bytes.buffer
            .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));

      // Same code path as the app with trip language = ja.
      final ocrText = await ocr.recognizeText(imgFile.path, linguaHint: 'ja');
      imgFile.deleteSync();

      // 1. character-level accuracy vs human transcription.
      final transcription = await rootBundle
          .loadString('test/fixtures/real_receipts/jp/$name.txt');
      final gt = _normalize(transcription);
      final hyp = _normalize(ocrText);
      final charAcc = gt.isEmpty
          ? 0.0
          : max(0.0, 1.0 - _levenshtein(gt, hyp) / gt.length);
      charAccSum += charAcc;

      // 2. end-to-end field accuracy (same rules as the host harness;
      // no linguaHint: the parser must recover the language on its own).
      final expected = jsonDecode(await rootBundle
              .loadString('test/fixtures/real_receipts/jp/$name.expected.json'))
          as Map<String, dynamic>;
      final result = ReceiptParser().parse(ocrText);

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
        fieldChecks++;
        if (ok) fieldHits++;
      }

      // Full recognized text, line by line (print truncates long payloads).
      // ignore: avoid_print
      print('--- OCR $name BEGIN ---');
      for (final line in ocrText.split('\n')) {
        // ignore: avoid_print
        print(line);
      }
      // ignore: avoid_print
      print('--- OCR $name END ---');

      report.writeln(
        '$name  '
        'charAcc=${(charAcc * 100).toStringAsFixed(1)}%  '
        'importo=${okImporto ? "OK" : "KO(${result.importo} != $expectedImporto)"}  '
        'data=${okData ? "OK" : "KO($actualDate != ${expected['data']})"}  '
        'valuta=${okValuta ? "OK" : "KO(${result.valuta})"}  '
        'fornitore=${okFornitore ? "OK" : "KO(${result.fornitore})"}  '
        'lingua=${result.lingua}',
      );
    }

    final fieldAcc = fieldHits / fieldChecks;
    final meanCharAcc = charAccSum / images.length;
    // ignore: avoid_print
    print('$report\n'
        'MLKIT CHAR ACCURACY (media 1-CER): '
        '${(meanCharAcc * 100).toStringAsFixed(1)}%\n'
        'MLKIT FIELD ACCURACY: $fieldHits/$fieldChecks = '
        '${(fieldAcc * 100).toStringAsFixed(1)}%');

    // The harness is a measurement, not a regression gate: it only fails if
    // OCR produced nothing at all.
    expect(fieldChecks, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Trim lines, collapse inner whitespace, drop empty lines — so that the CER
/// measures recognition errors, not formatting differences vs the manual
/// transcription.
String _normalize(String s) => s
    .split('\n')
    .map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((l) => l.isNotEmpty)
    .join('\n');

/// Two-row Levenshtein distance (code-unit level).
int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = min(min(prev[j] + 1, curr[j - 1] + 1), prev[j - 1] + cost);
    }
    final t = prev;
    prev = curr;
    curr = t;
  }
  return prev[b.length];
}
