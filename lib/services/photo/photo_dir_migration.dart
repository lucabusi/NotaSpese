import 'dart:io';

import 'package:path/path.dart' as p;

/// Outcome of a photo-directory migration. [error] is a ready-to-show
/// Italian message; the caller owns the SnackBar.
class MigrationResult {
  const MigrationResult.success(this.movedFiles) : error = null;
  const MigrationResult.failure(this.error) : movedFiles = 0;

  final int movedFiles;
  final String? error;

  bool get ok => error == null;
}

/// Moves the photo files when the user changes the photo directory in
/// Settings. Copy-all-then-delete, never a half state: if one copy fails the
/// copies are removed and the source files stay where they are.
///
/// The `foto` table stores paths RELATIVE to the photo base dir
/// (FotoRepository.basePathProvider), so moving the files keeps every stored
/// path valid — this service performs no DB write at all.
class PhotoDirMigrationService {
  const PhotoDirMigrationService();

  Future<MigrationResult> migrate({
    required Directory from,
    required Directory to,
  }) async {
    if (!from.existsSync() || p.equals(from.path, to.path)) {
      return const MigrationResult.success(0);
    }

    final sources = from.listSync(recursive: true).whereType<File>().toList();
    final copies = <File>[];
    // Directories created while copying (not already there beforehand), so
    // an abort can remove exactly what this migration added and nothing the
    // destination already had.
    final createdDirs = <String>{};
    try {
      for (final source in sources) {
        final relative = p.relative(source.path, from: from.path);
        final target = File(p.join(to.path, relative));
        var dir = target.parent;
        while (!dir.existsSync()) {
          createdDirs.add(dir.path);
          final parent = dir.parent;
          if (p.equals(parent.path, dir.path)) break;
          dir = parent;
        }
        await target.parent.create(recursive: true);
        await source.copy(target.path);
        copies.add(target);
      }
    } on FileSystemException {
      for (final copy in copies) {
        try {
          if (copy.existsSync()) await copy.delete();
        } on FileSystemException {
          // [NON-BLOCKING] a leftover copy wastes space; the source files
          // are still intact, which is what correctness depends on.
        }
      }
      // Deepest first so a parent directory is empty by the time it's
      // removed.
      final dirsDeepestFirst = createdDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final dirPath in dirsDeepestFirst) {
        try {
          final dir = Directory(dirPath);
          if (dir.existsSync()) await dir.delete();
        } on FileSystemException {
          // [NON-BLOCKING] same reasoning as FotoRepository.deleteFiles: a
          // leftover empty directory wastes a few bytes; the source files
          // are still intact, which is what correctness depends on.
        }
      }
      return const MigrationResult.failure(
          'Spostamento non riuscito: le foto sono rimaste nella cartella precedente.');
    }

    for (final source in sources) {
      try {
        if (source.existsSync()) await source.delete();
      } on FileSystemException {
        // [NON-BLOCKING] same reasoning as FotoRepository.deleteFiles: the
        // copies are already in place, an undeleted original is recoverable.
      }
    }
    return MigrationResult.success(copies.length);
  }
}
