import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';

/// Fullscreen receipt photo viewer: pinch zoom, share sheet, delete with
/// confirmation. [onDelete] (if provided) runs after the confirm dialog,
/// then the viewer pops.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.imagePath, this.onDelete});

  /// Absolute path of the full-size image.
  final String imagePath;
  final Future<void> Function()? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la foto?'),
        content: const Text('La spesa resta, la foto viene rimossa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed != true) return;
    await onDelete!();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('foto-share'),
            icon: const Icon(Symbols.share),
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(imagePath)])),
          ),
          if (onDelete != null)
            IconButton(
              key: const Key('foto-delete'),
              icon: const Icon(Symbols.delete),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}
