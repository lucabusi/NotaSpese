import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/core/constants/currencies.dart';
import 'package:nota_spese/version.dart';

void main() {
  // `appVersion` is what Settings shows; `pubspec.yaml` is what ends up in the
  // APK. They are two hand-maintained copies of the same fact, and they DID
  // drift (0.14.0+20 installed, "v0.13.1" on screen, 2026-08-20): the widget
  // tests compare the screen against the same constant, so only pubspec can
  // catch the mismatch.
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+?)\+', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no `version: x.y.z+build` in pubspec');
    expect(
      appVersion,
      match!.group(1),
      reason: 'bump lib/version.dart together with pubspec.yaml',
    );
  });

  group('Categoria', () {
    test('has the 10 categories from the spec', () {
      expect(Categoria.values.map((c) => c.name), [
        'pranzo', 'cena', 'colazione', 'trasporto', 'taxi',
        'hotel', 'parcheggio', 'carburante', 'telefono', 'altro',
      ]);
    });

    test('every category has a non-empty label and an icon', () {
      for (final c in Categoria.values) {
        expect(c.label, isNotEmpty);
        expect(c.icon, isNotNull);
      }
    });

    test('round-trips through name for DB storage', () {
      expect(Categoria.values.byName('taxi'), Categoria.taxi);
    });
  });

  group('Currency', () {
    test('does not include HRK (kuna replaced by EUR in 2023)', () {
      expect(Currency.values.where((c) => c.code == 'HRK'), isEmpty);
    });

    test('frequent currencies are the 8 from the spec, EUR first', () {
      expect(Currency.frequenti.map((c) => c.code), [
        'EUR', 'USD', 'JPY', 'GBP', 'CHF', 'RSD', 'AED', 'SGD',
      ]);
    });

    test('fromCode resolves known codes and returns null for unknown', () {
      expect(Currency.fromCode('JPY'), Currency.jpy);
      expect(Currency.fromCode('XXX'), isNull);
    });

    test('JPY has zero decimal digits', () {
      expect(Currency.jpy.decimalDigits, 0);
    });
  });
}
