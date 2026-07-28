import 'dart:io';

/// Disk usage of the photo directory, shown in Settings (Specifiche.md §11:
/// `Directory.stat()` does NOT report content size — the files must be
/// iterated and summed). Computed on demand (first section load + refresh
/// button), never polled.
class PhotoDirUsage {
  const PhotoDirUsage({required this.fileCount, required this.bytes});

  final int fileCount;
  final int bytes;

  static const PhotoDirUsage empty = PhotoDirUsage(fileCount: 0, bytes: 0);

  /// e.g. `12 file · 8,4 MB` (Italian decimal comma, one decimal).
  String get label {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
    return '$fileCount file · $mb MB';
  }

  static Future<PhotoDirUsage> measure(Directory dir) async {
    if (!dir.existsSync()) return empty;
    var count = 0;
    var bytes = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      count++;
      bytes += await entity.length();
    }
    return PhotoDirUsage(fileCount: count, bytes: bytes);
  }
}
