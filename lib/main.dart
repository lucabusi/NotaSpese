import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db/db_helper.dart';
import 'data/repositories/foto_repository.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';
import 'services/photo/photo_service.dart';
import 'services/photo/receipt_capture_service.dart';
import 'services/settings/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Manual composition (no DI package, Specifiche.md §Architettura).
  final dbHelper = DbHelper();
  final settingsService = SettingsService();

  // Single photo base dir shared by FotoRepository and PhotoService.
  // v1.0: app-specific dirs only (scoped storage, Specifiche.md §2);
  // external falls back to internal when unavailable.
  Future<String> photoBasePath() async {
    final kind = await settingsService.photoDirKind;
    final dir = kind == PhotoDirKind.external
        ? (await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'foto');
  }

  final fotoRepository =
      FotoRepository(dbHelper, basePathProvider: photoBasePath);
  final trasfertaRepository = TrasfertaRepository(dbHelper, fotoRepository);
  final spesaRepository = SpesaRepository(dbHelper, fotoRepository);
  final photoService =
      PhotoService(settingsService, basePathProvider: photoBasePath);
  final captureService = ReceiptCaptureService();

  runApp(NotaSpeseApp(
    trasfertaRepository: trasfertaRepository,
    spesaRepository: spesaRepository,
    fotoRepository: fotoRepository,
    photoService: photoService,
    captureService: captureService,
  ));
}
