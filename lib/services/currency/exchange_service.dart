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

/// EUR conversion from two chained sources. ECB reference rates
/// (frankfurter) come first because they are the ones citable in an expense
/// claim; a community source covers the ~10 currencies the ECB does not
/// publish (RSD, AED, KWD, QAR, SAR, TWD, VND, ALL, BAM, MKD).
/// Never throws toward callers: ANY failure — toggle off, offline, timeout,
/// non-200, malformed JSON, unknown currency, date outside a source's
/// history — returns null so the expense flow is never blocked.
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

  /// Currencies frankfurter answered 404 for: outside the ECB set, a
  /// permanent fact, so later conversions skip straight to the fallback.
  /// Only 404 lands here — a network failure must stay retryable.
  final Set<String> _ecbUnsupported = {};

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
    if (!_ecbUnsupported.contains(from)) {
      final ecb = await _fetchEcbRate(day, from);
      if (ecb.rate != null) return ecb.rate;
      if (ecb.unsupported) _ecbUnsupported.add(from);
    }
    return _fetchGlobalRate(day, from);
  }

  /// ECB rates via frankfurter. `unsupported` is true only on HTTP 404
  /// (currency outside the ECB set); every other failure leaves it false so
  /// the caller retries this source next time.
  Future<({double? rate, bool unsupported})> _fetchEcbRate(
      String day, String from) async {
    const failed = (rate: null, unsupported: false);
    final uri = Uri.https(
        'api.frankfurter.dev', '/v1/$day', {'from': from, 'to': 'EUR'});
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode == 404) return (rate: null, unsupported: true);
      if (response.statusCode != 200) return failed;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return failed;
      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) return failed;
      final rate = rates['EUR'];
      return (rate: rate is num ? rate.toDouble() : null, unsupported: false);
    } on Exception {
      // TimeoutException, SocketException, ClientException, FormatException:
      // all mapped to "no rate available, but retry this source later".
      return failed;
    }
  }

  /// Fallback source: daily historical files on a CDN, no API key. The rate
  /// is nested under the lowercased source currency, e.g. {"aed":{"eur":..}}.
  /// A 404 here means "no data for this day or currency" and is not cached:
  /// unlike the ECB set, it is not a permanent property of the currency.
  Future<double?> _fetchGlobalRate(String day, String from) async {
    final cur = from.toLowerCase();
    final uri = Uri.https('cdn.jsdelivr.net',
        '/npm/@fawazahmed0/currency-api@$day/v1/currencies/$cur.json');
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final rates = decoded[cur];
      if (rates is! Map<String, dynamic>) return null;
      final rate = rates['eur'];
      return rate is num ? rate.toDouble() : null;
    } on Exception {
      return null;
    }
  }

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
