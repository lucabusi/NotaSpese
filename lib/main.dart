import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db/db_helper.dart';
import 'data/repositories/foto_repository.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Manual composition (no DI package, Specifiche.md §Architettura).
  final dbHelper = DbHelper();
  final fotoRepository = FotoRepository(
    dbHelper,
    // Photo directory becomes configurable in fase 4 (SettingsService).
    basePathProvider: () async =>
        (await getApplicationDocumentsDirectory()).path,
  );
  final trasfertaRepository = TrasfertaRepository(dbHelper, fotoRepository);
  final spesaRepository = SpesaRepository(dbHelper, fotoRepository);

  runApp(NotaSpeseApp(
    trasfertaRepository: trasfertaRepository,
    spesaRepository: spesaRepository,
  ));
}
