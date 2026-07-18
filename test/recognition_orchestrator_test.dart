import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/ocr_service.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';
import 'package:nota_spese/services/ocr/receipt_parser.dart';
import 'package:nota_spese/services/ocr/recognition_orchestrator.dart';

class _FakeOcrService extends OcrService {
  _FakeOcrService({this.textToReturn = '', this.exceptionToThrow});

  final String textToReturn;
  final Object? exceptionToThrow;
  bool called = false;

  @override
  Future<String> recognizeText(String imagePath) async {
    called = true;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return textToReturn;
  }
}

class _FakeClaudeOcrService extends ClaudeOcrService {
  _FakeClaudeOcrService({this.result, this.exceptionToThrow})
      : super(apiKeyProvider: () async => 'dummy-not-used');

  final ParsedReceipt? result;
  final Object? exceptionToThrow;
  bool called = false;

  @override
  Future<ParsedReceipt> extract(String imagePath, {String? linguaHint}) async {
    called = true;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return result!;
  }
}

void main() {
  final parser = ReceiptParser();

  group('recognize: engine mlkit', () {
    test('calls mlkitOcr.recognizeText, applies parser, engine == mlkit', () async {
      final mlkit = _FakeOcrService(textToReturn: 'Bar Roma\nTotale 12,50\n18/07/2026');
      final claude = _FakeClaudeOcrService();
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.mlkit,
      );

      expect(mlkit.called, isTrue);
      expect(claude.called, isFalse);
      expect(result.receipt.engine, OcrEngine.mlkit);
      expect(result.receipt.rawText, 'Bar Roma\nTotale 12,50\n18/07/2026');
      expect(result.claudeFallbackToMlkit, isFalse);
    });
  });

  group('recognize: engine claude', () {
    test('working claude fake returns its ParsedReceipt, no mlkit call, no fallback', () async {
      final mlkit = _FakeOcrService();
      final claudeResult = const ParsedReceipt(
        importo: 42,
        valuta: 'EUR',
        fornitore: 'Claude Vendor',
        engine: OcrEngine.claude,
        rawText: '{"importo":42}',
      );
      final claude = _FakeClaudeOcrService(result: claudeResult);
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.claude,
      );

      expect(claude.called, isTrue);
      expect(mlkit.called, isFalse);
      expect(result.receipt, same(claudeResult));
      expect(result.receipt.engine, OcrEngine.claude);
      expect(result.claudeFallbackToMlkit, isFalse);
    });

    test('ClaudeOcrException falls back to mlkit path with flag true', () async {
      final mlkit = _FakeOcrService(textToReturn: 'Bar Roma\nTotale 12,50\n18/07/2026');
      final claude = _FakeClaudeOcrService(
        exceptionToThrow: ClaudeOcrException('boom'),
      );
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.claude,
      );

      expect(claude.called, isTrue);
      expect(mlkit.called, isTrue);
      expect(result.receipt.engine, OcrEngine.mlkit);
      expect(result.receipt.rawText, 'Bar Roma\nTotale 12,50\n18/07/2026');
      expect(result.claudeFallbackToMlkit, isTrue);
    });

    test('generic Exception from claude falls back to mlkit path with flag true', () async {
      final mlkit = _FakeOcrService(textToReturn: 'Bar Roma\nTotale 12,50\n18/07/2026');
      final claude = _FakeClaudeOcrService(
        exceptionToThrow: Exception('network down'),
      );
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.claude,
      );

      expect(result.receipt.engine, OcrEngine.mlkit);
      expect(result.claudeFallbackToMlkit, isTrue);
    });
  });

  group('mlkit throws: never surfaces to caller', () {
    test('direct mlkit path: mlkit throws -> empty ParsedReceipt engine mlkit', () async {
      final mlkit = _FakeOcrService(exceptionToThrow: Exception('camera glitch'));
      final claude = _FakeClaudeOcrService();
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.mlkit,
      );

      expect(result.receipt.engine, OcrEngine.mlkit);
      expect(result.receipt.isEmpty, isTrue);
      expect(result.receipt.rawText, '');
      expect(result.claudeFallbackToMlkit, isFalse);
    });

    test('fallback path: claude throws then mlkit also throws -> empty ParsedReceipt, fallback true',
        () async {
      final mlkit = _FakeOcrService(exceptionToThrow: Exception('camera glitch'));
      final claude = _FakeClaudeOcrService(
        exceptionToThrow: ClaudeOcrException('boom'),
      );
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: mlkit,
        claudeOcr: claude,
        parser: parser,
        apiKeyProvider: () async => null,
      );

      final result = await orchestrator.recognize(
        'foo.jpg',
        engine: OcrEngine.claude,
      );

      expect(result.receipt.engine, OcrEngine.mlkit);
      expect(result.receipt.isEmpty, isTrue);
      expect(result.receipt.rawText, '');
      expect(result.claudeFallbackToMlkit, isTrue);
    });
  });

  group('claudeAvailable', () {
    test('provider returns null -> false', () async {
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: _FakeOcrService(),
        claudeOcr: _FakeClaudeOcrService(),
        parser: parser,
        apiKeyProvider: () async => null,
      );

      expect(await orchestrator.claudeAvailable, isFalse);
    });

    test("provider returns '' -> false", () async {
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: _FakeOcrService(),
        claudeOcr: _FakeClaudeOcrService(),
        parser: parser,
        apiKeyProvider: () async => '',
      );

      expect(await orchestrator.claudeAvailable, isFalse);
    });

    test("provider returns 'sk-xxx' -> true", () async {
      final orchestrator = RecognitionOrchestrator(
        mlkitOcr: _FakeOcrService(),
        claudeOcr: _FakeClaudeOcrService(),
        parser: parser,
        apiKeyProvider: () async => 'sk-xxx',
      );

      expect(await orchestrator.claudeAvailable, isTrue);
    });
  });
}
