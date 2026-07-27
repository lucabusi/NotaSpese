import 'dart:io';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/foto_repository.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';
import 'services/backup/backup_service.dart';
import 'services/currency/exchange_service.dart';
import 'services/ocr/recognition_orchestrator.dart';
import 'services/photo/crop_service.dart';
import 'services/photo/photo_service.dart';
import 'services/photo/receipt_capture_service.dart';
import 'services/settings/api_key_store.dart';
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
    required this.apiKeyStore,
    required this.exchangeService,
    required this.cropService,
    required this.photoDirFor,
    required this.backupService,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;
  final FotoRepository fotoRepository;
  final PhotoService photoService;
  final ReceiptCaptureService captureService;
  final RecognitionOrchestrator orchestrator;
  final SettingsService settingsService;
  final ApiKeyStore apiKeyStore;
  final ExchangeService exchangeService;
  final CropService cropService;
  final Future<Directory> Function(PhotoDirKind) photoDirFor;
  final BackupService backupService;

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
        apiKeyStore: apiKeyStore,
        exchangeService: exchangeService,
        cropService: cropService,
        photoDirFor: photoDirFor,
        backupService: backupService,
      ),
    );
  }
}
