import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A crop expressed as fractions (0..1) of the decoded image, so the UI can
/// work in screen coordinates without knowing the real pixel size.
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const CropRect full =
      CropRect(left: 0, top: 0, right: 1, bottom: 1);

  /// A crop thinner than this on either axis is unusable (and, dragged to
  /// zero, would produce an empty image).
  static const double minSide = 0.05;

  /// Below this, a margin is a rounding artefact of the drag, not an intent
  /// to crop.
  static const double _fullTolerance = 0.005;

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool get isFull =>
      left <= _fullTolerance &&
      top <= _fullTolerance &&
      right >= 1 - _fullTolerance &&
      bottom >= 1 - _fullTolerance;

  /// Inside 0..1, sides in order, never thinner than [minSide].
  CropRect clamped() {
    var l = left.clamp(0.0, 1.0);
    var r = right.clamp(0.0, 1.0);
    var t = top.clamp(0.0, 1.0);
    var b = bottom.clamp(0.0, 1.0);
    if (l > r) (l, r) = (r, l);
    if (t > b) (t, b) = (b, t);
    if (r - l < minSide) {
      final centre = (l + r) / 2;
      l = (centre - minSide / 2).clamp(0.0, 1.0 - minSide);
      r = l + minSide;
    }
    if (b - t < minSide) {
      final centre = (t + b) / 2;
      t = (centre - minSide / 2).clamp(0.0, 1.0 - minSide);
      b = t + minSide;
    }
    return CropRect(left: l, top: t, right: r, bottom: b);
  }

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'CropRect($left, $top, $right, $bottom)';
}

/// Crops a captured photo before it reaches the OCR and PhotoService.
/// Pure Dart (`image` package) so the whole path is testable on the dev
/// machine, which cannot build for Android.
class CropService {
  CropService({Future<String> Function()? tempDirProvider})
      : _tempDirProvider =
            tempDirProvider ?? (() async => Directory.systemTemp.path);

  final Future<String> Function() _tempDirProvider;

  /// Quality of the intermediate file: the real compression is applied
  /// downstream by PhotoService, so this one stays near-lossless.
  static const int _jpgQuality = 95;

  /// Pixel size of [sourcePath], for the crop UI's aspect ratio.
  Future<(int, int)> sizeOf(String sourcePath) async {
    final decoded = await _decode(sourcePath);
    return (decoded.width, decoded.height);
  }

  /// Writes the crop as a temporary jpg and returns its path. With a rect
  /// that crops nothing, returns [sourcePath] itself: no re-encode, no
  /// quality lost for free.
  Future<String> crop(String sourcePath, CropRect rect) async {
    final safe = rect.clamped();
    if (safe.isFull) return sourcePath;

    final decoded = await _decode(sourcePath);
    // Floor the origin below the image edge: `clamped()` only guarantees
    // left/top <= 1 - minSide, so on a tiny source image rounding can still
    // push x/y to exactly decoded.width/height, leaving no room for the
    // width/height clamp below (whose upper bound would then be < 1).
    final x = (safe.left * decoded.width).round().clamp(0, decoded.width - 1);
    final y =
        (safe.top * decoded.height).round().clamp(0, decoded.height - 1);
    final width =
        (safe.width * decoded.width).round().clamp(1, decoded.width - x);
    final height =
        (safe.height * decoded.height).round().clamp(1, decoded.height - y);
    final cropped =
        img.copyCrop(decoded, x: x, y: y, width: width, height: height);

    final dir = await _tempDirProvider();
    final out = p.join(
        dir, 'CROP_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final file = File(out);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodeJpg(cropped, quality: _jpgQuality));
    return out;
  }

  // NOTE (verified against image 4.9.1): `img.decodeImage` on a JPEG
  // already bakes EXIF orientation into the pixel buffer and clears the
  // tag — see getImageFromJpeg in
  // formats/jpeg/_jpeg_quantize_io.dart, which rotates/flips per the
  // orientation tag before returning. `sizeOf`/`crop` below therefore see
  // the DISPLAYED dimensions and pixels for free; do not add a redundant
  // `img.bakeOrientation` call here — see crop_service_test.dart's "EXIF
  // orientation" group for the regression test that would catch a change
  // in this behaviour on a future `image` package upgrade.
  Future<img.Image> _decode(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    img.Image? decoded;
    Object? decodeError;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      // Some malformed buffers make the format sniffers in `image` throw
      // (e.g. a truncated PSD signature check) instead of returning null.
      decoded = null;
      decodeError = e;
    }
    if (decoded == null) {
      throw FormatException(
          'Immagine non valida: $sourcePath'
          '${decodeError != null ? ' ($decodeError)' : ''}');
    }
    return decoded;
  }
}
