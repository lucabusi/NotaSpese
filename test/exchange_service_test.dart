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
    expect(seen.path, '/2026-07-10');
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
    expect(seen.path, '/2026-01-05');
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
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1 ? http.Response('boom', 500) : ok(0.0061);
    });
    final s = service(client);
    expect(
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10)),
        isNull);
    final retry =
        await s.convert(amount: 10, from: 'JPY', date: DateTime(2026, 7, 10));
    expect(retry!.rate, 0.0061);
    expect(calls, 2);
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
}
