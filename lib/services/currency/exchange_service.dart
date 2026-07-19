import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/settings_service.dart';

/// Result of a EUR conversion: converted amount plus the rate used
/// (1 unit of the source currency = [rate] EUR).
class ExchangeResult {
  const ExchangeResult({required this.amountEur, required this.rate});

  final double amountEur;
  final double rate;
}

/// EUR conversion via frankfurter.app historical rates (fase 6 design).
/// Never throws toward callers: ANY failure — toggle off, offline, timeout,
/// non-200, malformed JSON, unsupported currency (frankfurter → 404, e.g.
/// RSD/AED are outside the ECB set) — returns null so the expense flow is
/// never blocked.
class ExchangeService {
  ExchangeService(this._settings,
      {http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  final SettingsService _settings;
  final http.Client _client;
  final Duration timeout;

  /// Session cache: 'yyyy-MM-dd|CUR' → rate. Historical rates never change,
  /// so entries stay valid for the whole app run.
  final Map<String, double> _rateCache = {};

  Future<ExchangeResult?> convert({
    required double amount,
    required String from,
    required DateTime date,
  }) async {
    if (from == 'EUR') return ExchangeResult(amountEur: amount, rate: 1.0);
    if (!await _settings.tassiOnline) return null;
    final day = _isoDay(date);
    final cacheKey = '$day|$from';
    var rate = _rateCache[cacheKey];
    if (rate == null) {
      rate = await _fetchRate(day, from);
      if (rate == null) return null;
      _rateCache[cacheKey] = rate;
    }
    return ExchangeResult(amountEur: amount * rate, rate: rate);
  }

  Future<double?> _fetchRate(String day, String from) async {
    final uri =
        Uri.https('api.frankfurter.app', '/$day', {'from': from, 'to': 'EUR'});
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) return null;
      final rate = rates['EUR'];
      return rate is num ? rate.toDouble() : null;
    } on Exception {
      // TimeoutException, SocketException, ClientException, FormatException:
      // all mapped to "no rate available".
      return null;
    }
  }

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
