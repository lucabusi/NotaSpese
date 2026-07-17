import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/spesa_repository.dart';
import 'data/repositories/trasferta_repository.dart';
import 'ui/shell/home_shell.dart';

class NotaSpeseApp extends StatelessWidget {
  const NotaSpeseApp({
    super.key,
    required this.trasfertaRepository,
    required this.spesaRepository,
  });

  final TrasfertaRepository trasfertaRepository;
  final SpesaRepository spesaRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nota Spese',
      theme: AppTheme.light(),
      home: HomeShell(
        trasfertaRepository: trasfertaRepository,
        spesaRepository: spesaRepository,
      ),
    );
  }
}
