import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../settings/settings_service.dart';

/// Relative paths (to the photo base dir) of a processed photo.
/// Stored as-is in the `foto` table; separator is always '/'.
class PhotoPaths {
  const PhotoPaths({required this.filePath, required this.thumbPath});

  final String filePath;
  final String thumbPath;
}

/// Filesystem-only photo pipeline (Specifiche.md §2): JPG compression
/// (quality from settings, default 70, max 1920px long side, never
/// upscaled) + 300px thumbnail in `thumbnails/`. The original source file
/// is left untouched (the caller deletes temp captures). DB records are
/// the caller's job (FotoRepository). Pure Dart (`image` package) so the
/// whole pipeline is unit-testable on this machine (no Android build).
class PhotoService {
  PhotoService(this._settings, {required this.basePathProvider});

  final SettingsService _settings;

  /// Same base dir used by FotoRepository (wired in main.dart).
  final Future<String> Function() basePathProvider;

  static const int maxLongSide = 1920;
  static const int thumbSize = 300;

  Future<String> absolutePath(String relative) async =>
      p.join(await basePathProvider(), relative);

  Future<PhotoPaths> process(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw FormatException('Immagine non valida: $sourcePath');
    }

    final quality = await _settings.jpgQuality;
    final resized = _shrinkTo(decoded, maxLongSide);
    final thumb = _shrinkTo(decoded, thumbSize);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    // Relative DB paths use '/' so they stay portable across platforms.
    final fileRel = 'IMG_$stamp.jpg';
    final thumbRel = 'thumbnails/IMG_${stamp}_thumb.jpg';

    final base = await basePathProvider();
    final file = File(p.join(base, fileRel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodeJpg(resized, quality: quality));
    final thumbFile = File(p.join(base, thumbRel));
    await thumbFile.parent.create(recursive: true);
    await thumbFile.writeAsBytes(img.encodeJpg(thumb, quality: quality));

    return PhotoPaths(filePath: fileRel, thumbPath: thumbRel);
  }

  static img.Image _shrinkTo(img.Image src, int longSide) {
    final long = src.width >= src.height ? src.width : src.height;
    if (long <= longSide) return src;
    return src.width >= src.height
        ? img.copyResize(src, width: longSide)
        : img.copyResize(src, height: longSide);
  }
}
