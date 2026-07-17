// Smoke test: the app builds with the home shell.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/app.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('App builds and shows the shell', (WidgetTester tester) async {
    // No-isolate factory: see trasferta_detail_screen_test.dart.
    final dbHelper = DbHelper(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    final trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    final spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    addTearDown(dbHelper.close);

    await tester.pumpWidget(NotaSpeseApp(
      trasfertaRepository: trasfertaRepo,
      spesaRepository: spesaRepo,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Trasferte'), findsWidgets);
    expect(find.text('Archivio'), findsOneWidget);
  });
}
