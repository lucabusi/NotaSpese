import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'parsed_receipt.dart';

/// Raised on any failure of [ClaudeOcrService.extract]. [message] is always
/// a generic, non-sensitive description: it never contains the API key,
/// request headers, or the raw response body (which could echo the key back
/// in an error payload).
class ClaudeOcrException implements Exception {
  ClaudeOcrException(this.message);

  final String message;

  @override
  String toString() => 'ClaudeOcrException: $message';
}

const Map<String, dynamic> _receiptSchema = {
  'type': 'object',
  'properties': {
    'importo': {'type': ['number', 'null']},
    'valuta': {'type': ['string', 'null'], 'description': 'ISO 4217'},
    'data': {'type': ['string', 'null'], 'description': 'YYYY-MM-DD'},
    'fornitore': {'type': ['string', 'null']},
    'lingua': {
      'type': ['string', 'null'],
      'enum': ['it', 'en', 'ja', 'sr', 'de', 'pl', null],
    },
  },
  'required': ['importo', 'valuta', 'data', 'fornitore', 'lingua'],
  'additionalProperties': false,
};

/// Cloud OCR/extraction backend: sends a receipt photo to the Claude Vision
/// API (raw HTTP — no SDK dependency on mobile) and gets structured fields
/// back via Anthropic's `output_config.format` (json_schema) feature.
///
/// The API key is read lazily via [apiKeyProvider] (backed by
/// [ApiKeyStore] in production) on every call, never cached in this
/// instance, and never appears in any exception message or log line.
class ClaudeOcrService {
  ClaudeOcrService({
    required Future<String?> Function() apiKeyProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  })  : // External name must stay `apiKeyProvider` per the task-8 spec,
        // while the field itself is private.
        // ignore: prefer_initializing_formals
        _apiKeyProvider = apiKeyProvider,
        _client = client ?? http.Client();

  final Future<String?> Function() _apiKeyProvider;
  final http.Client _client;
  final Duration timeout;

  static final Uri _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  Future<ParsedReceipt> extract(String imagePath, {String? linguaHint}) async {
    final apiKey = await _apiKeyProvider();
    if (apiKey == null || apiKey.isEmpty) {
      throw ClaudeOcrException('Chiave API Claude non configurata');
    }

    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    final promptBuffer = StringBuffer(
      'Estrai dallo scontrino in foto i campi importo, valuta (codice ISO '
      '4217), data (YYYY-MM-DD), fornitore e lingua. Rispondi seguendo lo '
      'schema JSON fornito.',
    );
    if (linguaHint != null && linguaHint.isNotEmpty) {
      promptBuffer.write(' Lingua probabile dello scontrino: $linguaHint.');
    }

    final body = jsonEncode({
      'model': 'claude-haiku-4-5',
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text': promptBuffer.toString(),
            },
          ],
        },
      ],
      'output_config': {
        'format': {
          'type': 'json_schema',
          'schema': _receiptSchema,
        },
      },
    });

    http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ClaudeOcrException('Timeout durante la chiamata a Claude');
    } on SocketException {
      throw ClaudeOcrException('Connessione assente durante la chiamata a Claude');
    }

    if (response.statusCode != 200) {
      throw ClaudeOcrException('Errore Claude: HTTP ${response.statusCode}');
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ClaudeOcrException('Risposta Claude non decodificabile');
    } on TypeError {
      throw ClaudeOcrException('Risposta Claude non decodificabile');
    }

    final content = decoded['content'];
    if (content is! List) {
      throw ClaudeOcrException('Risposta Claude senza campo content');
    }

    Map<String, dynamic>? textBlock;
    for (final block in content) {
      if (block is Map<String, dynamic> && block['type'] == 'text') {
        textBlock = block;
        break;
      }
    }
    if (textBlock == null) {
      throw ClaudeOcrException('Risposta Claude senza blocco di testo');
    }

    late final String rawText;
    Map<String, dynamic> fields;
    try {
      rawText = textBlock['text'] as String;
      fields = jsonDecode(rawText) as Map<String, dynamic>;
    } on FormatException {
      throw ClaudeOcrException('Campi Claude non decodificabili');
    } on TypeError {
      throw ClaudeOcrException('Campi Claude non decodificabili');
    }

    // Fields that don't match the declared json_schema (e.g. `importo` sent
    // back as a string) are treated as an API error, not surfaced as a raw
    // TypeError — spec: docs/superpowers/specs/2026-07-18-fase-5-ocr-parser-design.md.
    try {
      final dataStr = fields['data'] as String?;
      return ParsedReceipt(
        importo: (fields['importo'] as num?)?.toDouble(),
        valuta: fields['valuta'] as String?,
        data: dataStr == null ? null : DateTime.tryParse(dataStr),
        fornitore: fields['fornitore'] as String?,
        lingua: fields['lingua'] as String?,
        engine: OcrEngine.claude,
        rawText: rawText,
      );
    } on TypeError {
      throw ClaudeOcrException('Campi Claude in formato inatteso');
    }
  }
}
