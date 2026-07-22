import 'dart:math';

/// A recognized text line with its bounding box (pixel coordinates).
///
/// Pure-Dart mirror of ML Kit's `TextLine` + `boundingBox`, so the layout
/// reconstruction below is host-testable without the native plugin.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

/// Rebuilds the visual reading order from per-line bounding boxes.
///
/// ML Kit groups receipt text by COLUMN (all labels first, then all amounts),
/// which detaches labels from their values and breaks the parser. This
/// clusters lines into visual rows by vertical overlap, sorts each row
/// left-to-right and returns interlaced text ("合計 ¥1,100") like a human
/// transcription would.
String reconstructReadingOrder(List<OcrLine> lines) {
  if (lines.isEmpty) return '';
  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));

  final rows = <List<OcrLine>>[];
  var rowTop = 0.0;
  var rowBottom = 0.0;
  for (final line in sorted) {
    if (rows.isNotEmpty) {
      // Same visual row when the overlap covers >=50% of the shorter side.
      final overlap = min(rowBottom, line.bottom) - max(rowTop, line.top);
      final minHeight = min(rowBottom - rowTop, line.height);
      if (minHeight > 0 && overlap >= 0.5 * minHeight) {
        rows.last.add(line);
        rowTop = min(rowTop, line.top);
        rowBottom = max(rowBottom, line.bottom);
        continue;
      }
    }
    rows.add([line]);
    rowTop = line.top;
    rowBottom = line.bottom;
  }

  return rows
      .map((row) => (row..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text)
          .join(' '))
      .join('\n');
}
