import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'core/theme/app_theme.dart';
import 'version.dart';

class NotaSpeseApp extends StatelessWidget {
  const NotaSpeseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nota Spese',
      theme: AppTheme.light(),
      home: const _PlaceholderHome(),
    );
  }
}

/// Temporary home screen; replaced by HomeShell in phase 2.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nota Spese')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.receipt_long_rounded,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Nota Spese v$appVersion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
