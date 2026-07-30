import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nota_spese/services/currency/exchange_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response ok(double rate, {String date = '2026-07-10'}) => http.Response(
      jsonEncode({
        'amount': 1.0,
        'base': 'JPY',
        'date': date,
        'rates': {'EUR': rate},
      }),
      200,
      headers: {'content-type': 'application/json'});

  ExchangeService service(MockClient client) {
    SharedPreferences.setMockInitialValues({});
    return ExchangeService(SettingsService(), client: client);
  }

  test('historic rate: calls /yyyy-MM-dd?from=X&to=EUR and converts', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061);
    });
    final result = await service(client).convert(
        amount: 1200, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(seen.path, '/v1/2026-07-10');
    expect(seen.queryParameters, {'from': 'JPY', 'to': 'EUR'});
    expect(result!.rate, 0.0061);
    expect(result.amountEur, closeTo(7.32, 0.0001));
  });

  test('date components are zero-padded', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061, date: '2026-01-05');
    });
    await service(client)
        .convert(amount: 1, from: 'JPY', date: DateTime(2026, 1, 5));
    expect(seen.path, '/v1/2026-01-05');
  });

  test('EUR short-circuits without any network call', () async {
    final client = MockClient((request) async {
      fail('network must not be touched for EUR');
    });
    final result = await service(client)
        .convert(amount: 42.5, from: 'EUR', date: DateTime(2026, 7, 10));
    expect(result!.rate, 1.0);
    expect(result.amountEur, 42.5);
  });

  test('HTTP 404 (unsupported currency, e.g. RSD) returns null', () async {
    final client = MockClient((request) async => http.Response('not found', 404));
    expect(
        await service(client)
            .convert(amount: 10, from: 'RSD', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('HTTP 500 returns null', () async {
    final client = MockClient((request) async => http.Response('boom', 500));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('SocketException (offline) returns null', () async {
    final client = MockClient((request) async {
      throw const SocketException('offline');
    });
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('timeout returns null', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return ok(0.0061);
    });
    SharedPreferences.setMockInitialValues({});
    final s = ExchangeService(SettingsService(),
        client: client, timeout: const Duration(milliseconds: 50));
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('malformed JSON returns null', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('missing rates key returns null', () async {
    final client =
        MockClient((request) async => http.Response(jsonEncode({'a': 1}), 200));
    expect(
        await service(client)
            .convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  test('same date+currency is served from cache (single fetch)', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return ok(0.0061);
    });
    final s = service(client);
    await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10));
    await s.convert(amount: 99, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(calls, 1);
    await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 11));
    expect(calls, 2);
  });

  test('failed fetch is not cached (retry hits network again)', () async {
    // Counts ECB calls only: a failing lookup also runs the fallback source,
    // so the total request count is no longer a proxy for "retried".
    var ecbCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host != 'api.frankfurter.dev') {
        return http.Response('not found', 404);
      }
      ecbCalls++;
      return ecbCalls == 1 ? http.Response('boom', 500) : ok(0.0061);
    });
    final s = service(client);
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
    final retry =
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(retry!.rate, 0.0061);
    expect(ecbCalls, 2);
  });

  test('tassi_online off returns null without network', () async {
    final client = MockClient((request) async {
      fail('network must not be touched when toggle is off');
    });
    SharedPreferences.setMockInitialValues({'tassi_online': false});
    final s = ExchangeService(SettingsService(), client: client);
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
  });

  // --- two-source chain: ECB first, global fallback for what it lacks ---

  http.Response globalOk(String cur, double rate) => http.Response(
      jsonEncode({
        'date': '2026-07-10',
        cur: {'usd': 1.0, 'eur': rate},
      }),
      200,
      headers: {'content-type': 'application/json'});

  test('ECB path uses api.frankfurter.dev with the /v1 prefix', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return ok(0.0061);
    });
    await service(client)
        .convert(amount: 100, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(seen.host, 'api.frankfurter.dev');
    expect(seen.path, '/v1/2026-07-10');
    expect(seen.queryParameters, {'from': 'JPY', 'to': 'EUR'});
  });

  test('ECB 404 falls back to the global source and converts', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      if (request.url.host == 'api.frankfurter.dev') {
        return http.Response('not found', 404);
      }
      return globalOk('aed', 0.2345);
    });
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2026, 7, 10));
    expect(result!.rate, 0.2345);
    expect(result.amountEur, closeTo(23.45, 0.0001));
    expect(urls.last.host, 'cdn.jsdelivr.net');
    expect(urls.last.path,
        '/npm/@fawazahmed0/currency-api@2026-07-10/v1/currencies/aed.json');
  });

  test('ECB timeout falls back to the global source', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.frankfurter.dev') {
        throw const SocketException('offline');
      }
      return globalOk('rsd', 0.0085);
    });
    final result = await service(client)
        .convert(amount: 1000, from: 'RSD', date: DateTime(2026, 7, 10));
    expect(result!.rate, 0.0085);
  });

  test('both sources failing yields null, never throws', () async {
    final client = MockClient((request) async => http.Response('nope', 500));
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2026, 7, 10));
    expect(result, isNull);
  });

  test('a 404-ed currency skips ECB on the next call', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'api.frankfurter.dev') {
        return http.Response('not found', 404);
      }
      return globalOk('aed', 0.2345);
    });
    final s = service(client);
    await s.convert(amount: 1, from: 'AED', date: DateTime(2026, 7, 10));
    // Different day so the rate cache cannot serve it.
    await s.convert(amount: 1, from: 'AED', date: DateTime(2026, 7, 11));
    expect(hosts, [
      'api.frankfurter.dev',
      'cdn.jsdelivr.net',
      'cdn.jsdelivr.net',
    ]);
  });

  test('an ECB network failure is transient: next call retries ECB', () async {
    var ecbCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.frankfurter.dev') {
        ecbCalls++;
        if (ecbCalls == 1) throw const SocketException('offline');
        return ok(0.0061);
      }
      return globalOk('jpy', 0.0060);
    });
    final s = service(client);
    await s.convert(amount: 1, from: 'JPY', date: DateTime(2026, 7, 10));
    final second =
        await s.convert(amount: 1, from: 'JPY', date: DateTime(2026, 7, 11));
    expect(second!.rate, 0.0061, reason: 'ECB must be retried, not skipped');
    expect(ecbCalls, 2);
  });

  test('global source 404 (date before its history) yields null', () async {
    final client =
        MockClient((request) async => http.Response('not found', 404));
    final result = await service(client)
        .convert(amount: 100, from: 'AED', date: DateTime(2020, 1, 15));
    expect(result, isNull);
  });
}
