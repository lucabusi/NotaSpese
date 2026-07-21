import 'dart:io';

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
  /// building, or widget tests (FakeAsync) would hang on it.
  static Future<String?> show(
    BuildContext context, {
    required String imagePath,
    required CropService cropService,
  }) async {
    final (width, height) = await cropService.sizeOf(imagePath);
    if (!context.mounted) return null;
    return Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => CropScreen(
        imagePath: imagePath,
        imageWidth: width,
        imageHeight: height,
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
  static const double _handleSize = 44;

  /// In coordinates of the displayed box (which, thanks to the
  /// [AspectRatio] below, coincides with the image itself).
  Rect? _rect;

  /// Latest box size, kept for the box→fractions conversion on confirm and
  /// for clamping drags.
  Size _boxSize = Size.zero;

  void _updateCorner(_Corner corner, Offset delta) {
    final r = _rect!;
    Rect moved;
    switch (corner) {
      case _Corner.topLeft:
        moved = Rect.fromLTRB(
            r.left + delta.dx, r.top + delta.dy, r.right, r.bottom);
      case _Corner.topRight:
        moved = Rect.fromLTRB(
            r.left, r.top + delta.dy, r.right + delta.dx, r.bottom);
      case _Corner.bottomLeft:
        moved = Rect.fromLTRB(
            r.left + delta.dx, r.top, r.right, r.bottom + delta.dy);
      case _Corner.bottomRight:
        moved = Rect.fromLTRB(
            r.left, r.top, r.right + delta.dx, r.bottom + delta.dy);
    }
    setState(() => _rect = _clamp(moved));
  }

  /// The single rule that keeps a dragged rect inside the box and no
  /// thinner than [CropRect.minSide]: convert to fractions, reuse
  /// [CropRect.clamped], convert back. No separate pixel-space minimum.
  Rect _clamp(Rect r) {
    final box = _boxSize;
    final fraction = CropRect(
      left: r.left / box.width,
      top: r.top / box.height,
      right: r.right / box.width,
      bottom: r.bottom / box.height,
    ).clamped();
    return Rect.fromLTRB(
      fraction.left * box.width,
      fraction.top * box.height,
      fraction.right * box.width,
      fraction.bottom * box.height,
    );
  }

  Future<void> _confirm() async {
    final box = _boxSize;
    final r = _rect!;
    final rect = CropRect(
      left: r.left / box.width,
      top: r.top / box.height,
      right: r.right / box.width,
      bottom: r.bottom / box.height,
    );
    final result = await widget.cropService.crop(widget.imagePath, rect);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Widget _handle(_Corner corner) {
    final r = _rect!;
    final center = switch (corner) {
      _Corner.topLeft => r.topLeft,
      _Corner.topRight => r.topRight,
      _Corner.bottomLeft => r.bottomLeft,
      _Corner.bottomRight => r.bottomRight,
    };
    return Positioned(
      left: center.dx - _handleSize / 2,
      top: center.dy - _handleSize / 2,
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
              _rect ??= Offset.zero & _boxSize;
              final rect = _rect!;
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
                    child: Container(
                      key: const Key('crop-riquadro'),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
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
