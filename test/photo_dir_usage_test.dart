import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/services/photo/photo_dir_usage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('usage_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('missing directory measures as empty', () async {
    final usage =
        await PhotoDirUsage.measure(Directory(p.join(root.path, 'nope')));

    expect(usage.fileCount, 0);
    expect(usage.bytes, 0);
    expect(usage.label, '0 file · 0,0 MB');
  });

  test('sums files recursively, thumbnails included', () async {
    File(p.join(root.path, 'IMG_1.jpg'))
        .writeAsBytesSync(List.filled(1024 * 1024, 7));
    final thumbs = Directory(p.join(root.path, 'thumbnails'))
      ..createSync(recursive: true);
    File(p.join(thumbs.path, 'IMG_1_thumb.jpg'))
        .writeAsBytesSync(List.filled(512 * 1024, 7));

    final usage = await PhotoDirUsage.measure(root);

    expect(usage.fileCount, 2);
    expect(usage.bytes, 1024 * 1024 + 512 * 1024);
    expect(usage.label, '2 file · 1,5 MB');
  });
}
