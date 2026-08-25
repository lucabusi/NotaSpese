import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nota_spese/services/ocr/claude_ocr_service.dart';
import 'package:nota_spese/services/ocr/parsed_receipt.dart';

void main() {
  late Directory tempDir;
  late File imageFile;
  late List<int> imageBytes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('claude_ocr_test');
    imageFile = File('${tempDir.path}/receipt.jpg');
    imageBytes = List<int>.generate(64, (i) => i % 256);
    imageFile.writeAsBytesSync(imageBytes);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> successResponseJson(Map<String, dynamic> fields) => {
        'content': [
          {'type': 'text', 'text': jsonEncode(fields)},
        ],
      };

  test('success: sends correct request and maps response', () async {
    late http.Request capturedRequest;
    final mockClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode(successResponseJson({
          'importo': 12.5,
          'valuta': 'EUR',
          'data': '2026-07-18',
          'fornitore': 'Bar Roma',
          'lingua': 'it',
        })),
        200,
      );
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
    );

    final result = await service.extract(imageFile.path, linguaHint: 'it');

    // Request shape.
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url, Uri.parse('https://api.anthropic.com/v1/messages'));
    expect(capturedRequest.headers['x-api-key'], 'sk-test-key-123');
    expect(capturedRequest.headers['anthropic-version'], '2023-06-01');
    expect(capturedRequest.headers['content-type'], contains('application/json'));

    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-haiku-4-5');
    expect(body['max_tokens'], 1024);

    final content =
        (body['messages'] as List)[0]['content'] as List<dynamic>;
    final imageBlock =
        content.firstWhere((b) => (b as Map)['type'] == 'image') as Map;
    expect(imageBlock['source']['type'], 'base64');
    expect(imageBlock['source']['media_type'], 'image/jpeg');
    expect(imageBlock['source']['data'], base64Encode(imageBytes));

    final textBlock =
        content.firstWhere((b) => (b as Map)['type'] == 'text') as Map;
    expect(textBlock['text'], contains('Lingua probabile dello scontrino: it'));

    final format = body['output_config']['format'] as Map;
    expect(format['type'], 'json_schema');
    final schema = format['schema'] as Map;
    expect(schema['additionalProperties'], false);
    expect(schema['required'], containsAll(['importo', 'valuta', 'data', 'fornitore', 'lingua']));
    final linguaSchema =
        (schema['properties'] as Map)['lingua'] as Map<String, dynamic>;
    expect(linguaSchema['enum'], containsAll(['it', 'en', 'ja', 'sr', 'de', 'pl']));

    // Response mapping.
    expect(result.engine, OcrEngine.claude);
    expect(result.importo, 12.5);
    expect(result.valuta, 'EUR');
    expect(result.data, DateTime.parse('2026-07-18'));
    expect(result.fornitore, 'Bar Roma');
    expect(result.lingua, 'it');
    expect(result.rawText, isNotEmpty);
  });

  test('does not append a lingua hint when linguaHint is absent', () async {
    late http.Request capturedRequest;
    final mockClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode(successResponseJson({
          'importo': 12.5,
          'valuta': 'EUR',
          'data': '2026-07-18',
          'fornitore': 'Bar Roma',
          'lingua': 'it',
        })),
        200,
      );
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
    );

    await service.extract(imageFile.path);

    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    final content = (body['messages'] as List)[0]['content'] as List<dynamic>;
    final textBlock =
        content.firstWhere((b) => (b as Map)['type'] == 'text') as Map;
    expect(textBlock['text'], isNot(contains('Lingua probabile')));
  });

  test(
      'schema-mismatched field (importo as string) throws ClaudeOcrException, '
      'not a raw TypeError', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode(successResponseJson({
          'importo': '12.50', // wrong type per schema (should be number)
          'valuta': 'EUR',
          'data': '2026-07-18',
          'fornitore': 'Bar Roma',
          'lingua': 'it',
        })),
        200,
      );
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
    );

    await expectLater(
      () => service.extract(imageFile.path),
      throwsA(isA<ClaudeOcrException>()),
    );
  });

  test('401 status throws ClaudeOcrException without leaking key or body',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"error":{"message":"invalid x-api-key: sk-test-key-123"}}', 401);
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
    );

    try {
      await service.extract(imageFile.path);
      fail('should have thrown');
    } on ClaudeOcrException catch (e) {
      expect(e.message, isNot(contains('sk-test-key-123')));
      expect(e.message, isNot(contains('invalid x-api-key')));
    }
  });

  test('timeout throws ClaudeOcrException', () async {
    final mockClient = MockClient((request) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
      timeout: const Duration(milliseconds: 10),
    );

    expect(
      () => service.extract(imageFile.path),
      throwsA(isA<ClaudeOcrException>()),
    );
  });

  test('non-JSON response throws ClaudeOcrException', () async {
    final mockClient = MockClient((request) async {
      return http.Response('not json at all', 200);
    });

    final service = ClaudeOcrService(
      apiKeyProvider: () async => 'sk-test-key-123',
      client: mockClient,
    );

    expect(
      () => service.extract(imageFile.path),
      throwsA(isA<ClaudeOcrException>()),
    );
  });

  test('null/empty key throws without any HTTP call', () async {
    final mockClient = MockClient((request) async {
      fail('HTTP client must not be invoked when the key is missing');
    });

    final serviceNullKey = ClaudeOcrService(
      apiKeyProvider: () async => null,
      client: mockClient,
    );
    await expectLater(
      () => serviceNullKey.extract(imageFile.path),
      throwsA(isA<ClaudeOcrException>()),
    );

    final serviceEmptyKey = ClaudeOcrService(
      apiKeyProvider: () async => '',
      client: mockClient,
    );
    await expectLater(
      () => serviceEmptyKey.extract(imageFile.path),
      throwsA(isA<ClaudeOcrException>()),
    );
  });
}
