import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/foto_repository.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';
import 'services/ocr/recognition_orchestrator.dart';
import 'services/photo/photo_service.dart';
import 'services/photo/receipt_capture_service.dart';
import 'services/settings/settings_service.dart';
import 'ui/shell/home_shell.dart';

class NotaSpeseApp extends StatelessWidget {
  const NotaSpeseApp({
    super.key,
    required this.trasfertaRepository,
    required this.spesaRepository,
    required this.fotoRepository,
    required this.photoService,
    required this.captureService,
    required this.orchestrator,
    required this.settingsService,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;
  final FotoRepository fotoRepository;
  final PhotoService photoService;
  final ReceiptCaptureService captureService;
  final RecognitionOrchestrator orchestrator;
  final SettingsService settingsService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nota Spese',
      theme: AppTheme.light(),
      home: HomeShell(
        trasfertaRepository: trasfertaRepository,
        spesaRepository: spesaRepository,
        fotoRepository: fotoRepository,
        photoService: photoService,
        captureService: captureService,
        orchestrator: orchestrator,
        settingsService: settingsService,
      ),
    );
  }
}
