// Smoke test: the app builds and shows the placeholder home.

import 'package:flutter_test/flutter_test.dart';

import 'package:nota_spese/app.dart';
import 'package:nota_spese/version.dart';

void main() {
  testWidgets('App builds and shows version', (WidgetTester tester) async {
    await tester.pumpWidget(const NotaSpeseApp());

    expect(find.text('Nota Spese'), findsOneWidget);
    expect(find.text('Nota Spese v$appVersion'), findsOneWidget);
  });
}
