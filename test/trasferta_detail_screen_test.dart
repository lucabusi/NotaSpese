import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/db/db_helper.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/data/repositories/foto_repository.dart';
import 'package:nota_spese/data/repositories/spesa_repository.dart';
import 'package:nota_spese/data/repositories/trasferta_repository.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_controller.dart';
import 'package:nota_spese/ui/trasferte/trasferta_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper dbHelper;
  late TrasfertaRepository trasfertaRepo;
  late SpesaRepository spesaRepo;
  late int trasfertaId;

  setUp(() async {
    // No-isolate factory: futures complete as microtasks, so widget tests
    // (FakeAsync) don't hang waiting on a real isolate response.
    dbHelper = DbHelper(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    final fotoRepo = FotoRepository(dbHelper,
        basePathProvider: () async => Directory.systemTemp.path);
    trasfertaRepo = TrasfertaRepository(dbHelper, fotoRepo);
    spesaRepo = SpesaRepository(dbHelper, fotoRepo);
    trasfertaId = await trasfertaRepo.insert(Trasferta(
      nome: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      createdAt: DateTime(2026, 7, 9),
    ));
  });

  tearDown(() => dbHelper.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TrasfertaDetailScreen(
        controller:
            TrasfertaDetailController(trasfertaId, trasfertaRepo, spesaRepo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no spese', (tester) async {
    await pump(tester);

    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Nessuna spesa registrata'), findsOneWidget);
    expect(find.text('€ 0,00'), findsOneWidget);
  });

  testWidgets('lists spese grouped by date', (tester) async {
    await spesaRepo.insert(Spesa(
      trasfertaId: trasfertaId,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      fornitore: 'Ichiran',
      importo: 3000,
      valuta: 'JPY',
      createdAt: DateTime(2026, 7, 11, 21),
    ));

    await pump(tester);

    expect(find.text('11/07/2026'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    // Amount appears twice: per-currency total in the header + spesa tile.
    expect(find.textContaining('3.000'), findsWidgets);
    expect(find.text('Nessuna spesa registrata'), findsNothing);
  });

  testWidgets('FAB shows fase-3 placeholder snackbar', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.textContaining('fase 3'), findsOneWidget);
  });

  testWidgets('elimina asks confirmation and cancel keeps the trip',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(PopupMenuButton<DetailAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Eliminare'), findsOneWidget); // dialog

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(await trasfertaRepo.getById(trasfertaId), isNotNull);
  });
}
