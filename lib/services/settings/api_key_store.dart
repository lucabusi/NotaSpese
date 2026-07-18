import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around the platform keystore for the Claude API key
/// (Specifiche.md — mai in chiaro su SharedPreferences/DB). Instance methods
/// so callers can inject a fake; the real storage isn't host-testable
/// (pattern: ReceiptCaptureService).
class ApiKeyStore {
  ApiKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _key = 'claude_api_key';

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String value) => _storage.write(key: _key, value: value);

  Future<void> delete() => _storage.delete(key: _key);
}
