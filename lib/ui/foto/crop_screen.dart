import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../services/photo/crop_service.dart';

/// Crop step between the capture and the OCR: the rect starts on the whole
/// image, so a scan the Document Scanner already framed well only needs a
/// tap on Conferma.
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.cropService,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final CropService cropService;

  /// Reads the pixel size BEFORE pushing: the widget must not do IO while
  /// building, or widget tests (FakeAsync) would hang on it. A full JPEG
  /// decode of a scanner-sized photo can take seconds, so it runs behind a
  /// blocking progress dialog; if it throws (corrupt file, full disk) the
  /// user sees a snackbar instead of a silently stuck flow.
  static Future<String?> show(
    BuildContext context, {
    required String imagePath,
    required CropService cropService,
  }) async {
    final size = await _runBlocking(context, () => cropService.sizeOf(imagePath));
    if (size == null) {
      if (context.mounted) _showUnreadableSnackbar(context);
      return null;
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => CropScreen(
        imagePath: imagePath,
        imageWidth: size.$1,
        imageHeight: size.$2,
        cropService: cropService,
      ),
    ));
  }

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CropScreenState extends State<CropScreen> {
  /// Touch target side of a corner handle (Material minimum tap target).
  /// [_handle] clamps the target's position inward so the full 44x44
  /// stays inside the box even when its corner sits on a box edge
  /// (routine at the initial full-image rect): centering it ON the corner
  /// there would put half of it past the Stack's hard clip, leaving only
  /// ~22x22 actually reachable.
  static const double _handleSize = 44;

  /// Single source of truth for the crop, as fractions of the image
  /// (0..1) — NOT pixels of the displayed box. Box-local pixels go stale
  /// the moment the box is resized (e.g. a device rotation): the pixel
  /// rect for display is always re-derived from this and the latest
  /// [_boxSize] in [_pixelRect], so a resize can never leave a rect that
  /// exceeds the new box or handles that land outside it.
  CropRect _cropRect = CropRect.full;

  /// Latest box size, kept for the fractions→pixels conversion used both
  /// to paint and to convert a drag's pixel delta back into fractions.
  Size _boxSize = Size.zero;

  Rect _pixelRect() => Rect.fromLTRB(
        _cropRect.left * _boxSize.width,
        _cropRect.top * _boxSize.height,
        _cropRect.right * _boxSize.width,
        _cropRect.bottom * _boxSize.height,
      );

  void _updateCorner(_Corner corner, Offset delta) {
    final box = _boxSize;
    if (box.width == 0 || box.height == 0) return;
    final dx = delta.dx / box.width;
    final dy = delta.dy / box.height;
    final r = _cropRect;
    CropRect moved;
    switch (corner) {
      case _Corner.topLeft:
        moved =
            CropRect(left: r.left + dx, top: r.top + dy, right: r.right, bottom: r.bottom);
      case _Corner.topRight:
        moved = CropRect(
            left: r.left, top: r.top + dy, right: r.right + dx, bottom: r.bottom);
      case _Corner.bottomLeft:
        moved = CropRect(
            left: r.left + dx, top: r.top, right: r.right, bottom: r.bottom + dy);
      case _Corner.bottomRight:
        moved = CropRect(
            left: r.left, top: r.top, right: r.right + dx, bottom: r.bottom + dy);
    }
    setState(() => _cropRect = moved.clamped());
  }

  /// Pan on the rect's body: translates it (size unchanged) rather than
  /// resizing, clamped so it never crosses the box edge. `clamped()` isn't
  /// reused here — it would shrink an out-of-bounds rect instead of
  /// sliding it back in, which is the wrong behaviour for a translation.
  void _translateBody(Offset delta) {
    final box = _boxSize;
    if (box.width == 0 || box.height == 0) return;
    final dx = delta.dx / box.width;
    final dy = delta.dy / box.height;
    final r = _cropRect;
    final left = (r.left + dx).clamp(0.0, 1.0 - r.width);
    final top = (r.top + dy).clamp(0.0, 1.0 - r.height);
    setState(() => _cropRect = CropRect(
        left: left, top: top, right: left + r.width, bottom: top + r.height));
  }

  /// Guards against a second tap queuing a second decode/crop (and a
  /// second `pop`) while the first is still running.
  bool _confirming = false;

  Future<void> _confirm() async {
    if (_confirming) return;
    _confirming = true;
    final result = await _runBlocking(
        context, () => widget.cropService.crop(widget.imagePath, _cropRect));
    _confirming = false;
    if (result == null) {
      if (mounted) _showUnreadableSnackbar(context);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Widget _handle(_Corner corner) {
    final r = _pixelRect();
    final center = switch (corner) {
      _Corner.topLeft => r.topLeft,
      _Corner.topRight => r.topRight,
      _Corner.bottomLeft => r.bottomLeft,
      _Corner.bottomRight => r.bottomRight,
    };
    // Clamped into [0, boxSize - handleSize] rather than centred on the
    // corner: at the initial full rect the corner sits exactly on the box
    // edge, so a centred 44x44 target would be half outside it (and
    // clipped). The visual dot (below) stays centred within whatever
    // 44x44 this produces, so in that situation it sits slightly inward
    // of the true corner rather than off the edge and untappable.
    final maxLeft = math.max(0.0, _boxSize.width - _handleSize);
    final maxTop = math.max(0.0, _boxSize.height - _handleSize);
    final left = (center.dx - _handleSize / 2).clamp(0.0, maxLeft);
    final top = (center.dy - _handleSize / 2).clamp(0.0, maxTop);
    return Positioned(
      left: left,
      top: top,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        key: Key('crop-handle-${_cornerKeySuffix(corner)}'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _updateCorner(corner, details.delta),
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.primary, width: 2),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  static String _cornerKeySuffix(_Corner corner) => switch (corner) {
        _Corner.topLeft => 'tl',
        _Corner.topRight => 'tr',
        _Corner.bottomLeft => 'bl',
        _Corner.bottomRight => 'br',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Ritaglia scontrino'),
        leading: IconButton(
          key: const Key('crop-annulla'),
          icon: const Icon(Symbols.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            key: const Key('crop-conferma'),
            icon: const Icon(Symbols.check),
            onPressed: _confirm,
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: widget.imageWidth / widget.imageHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _boxSize = Size(constraints.maxWidth, constraints.maxHeight);
              final rect = _pixelRect();
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(
                      File(widget.imagePath),
                      key: const Key('crop-immagine'),
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ShadeOutsidePainter(rect),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rect,
                    child: GestureDetector(
                      key: const Key('crop-corpo'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => _translateBody(details.delta),
                      child: Container(
                        key: const Key('crop-riquadro'),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                  _handle(_Corner.topLeft),
                  _handle(_Corner.topRight),
                  _handle(_Corner.bottomLeft),
                  _handle(_Corner.bottomRight),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Darkens everything outside the crop rect, so what will be kept is
/// visually obvious without reading any label.
class _ShadeOutsidePainter extends CustomPainter {
  _ShadeOutsidePainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _ShadeOutsidePainter oldDelegate) =>
      oldDelegate.rect != rect;
}

void _showUnreadableSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Immagine non leggibile')));
}

/// Runs [operation] behind a full-screen, non-cancellable progress dialog
/// (same visual language as [showOcrProgress] in ocr_progress.dart): a
/// synchronous decode/crop of a scanner-sized photo can freeze the UI for
/// seconds, so something must be on screen while it runs. Returns the
/// result, or null if [operation] threw (the caller decides how to surface
/// that: [CropScreen] shows a snackbar and stays put).
Future<T?> _runBlocking<T>(
  BuildContext context,
  Future<T> Function() operation,
) {
  return showDialog<T?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _BlockingProgressDialog<T>(operation: operation),
  );
}

class _BlockingProgressDialog<T> extends StatefulWidget {
  const _BlockingProgressDialog({required this.operation});

  final Future<T> Function() operation;

  @override
  State<_BlockingProgressDialog<T>> createState() =>
      _BlockingProgressDialogState<T>();
}

class _BlockingProgressDialogState<T>
    extends State<_BlockingProgressDialog<T>> {
  @override
  void initState() {
    super.initState();
    widget.operation().then((value) {
      if (!mounted) return;
      Navigator.of(context).pop(value);
    }).catchError((_) {
      // The operation itself already logged/threw; this dialog only needs
      // to get out of the way so the caller can show a snackbar and decide
      // what to do next.
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: AppColors.surfaceDark,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
