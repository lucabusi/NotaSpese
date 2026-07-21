import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:path/path.dart' as p;

void main() {
  // Real receipt, versioned with the repo: 696x2000.
  const sourcePath = 'scontrini_training/scontrino_JP_01.jpg';

  late Directory tempDir;
  late CropService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crop_service_test');
    service = CropService(tempDirProvider: () async => tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('CropRect.clamped', () {
    test('keeps an already valid rect untouched', () {
      const rect = CropRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.9);
      expect(rect.clamped(), rect);
    });

    test('pulls values back inside 0..1', () {
      const rect = CropRect(left: -0.3, top: -1, right: 1.4, bottom: 2);
      expect(rect.clamped(), CropRect.full);
    });

    test('swaps inverted sides', () {
      const rect = CropRect(left: 0.8, top: 0.9, right: 0.2, bottom: 0.1);
      expect(rect.clamped(),
          const CropRect(left: 0.2, top: 0.1, right: 0.8, bottom: 0.9));
    });

    test('grows a side thinner than minSide around its centre', () {
      const rect = CropRect(left: 0.5, top: 0.1, right: 0.51, bottom: 0.9);
      final clamped = rect.clamped();
      expect(clamped.width, closeTo(CropRect.minSide, 1e-9));
      expect((clamped.left + clamped.right) / 2, closeTo(0.505, 1e-9));
      expect(clamped.top, 0.1); // the other axis is left alone
    });
  });

  group('CropRect.isFull', () {
    test('true for the full rect and for imperceptible margins', () {
      expect(CropRect.full.isFull, isTrue);
      expect(
          const CropRect(left: 0.001, top: 0, right: 0.999, bottom: 1).isFull,
          isTrue);
    });

    test('false once a real slice is cut', () {
      expect(const CropRect(left: 0.1, top: 0, right: 1, bottom: 1).isFull,
          isFalse);
    });
  });

  group('CropService.crop', () {
    test('writes a jpg with the cropped pixel size', () async {
      final out = await service.crop(sourcePath,
          const CropRect(left: 0.25, top: 0.5, right: 0.75, bottom: 1));

      expect(out, isNot(sourcePath));
      expect(p.isWithin(tempDir.path, out), isTrue,
          reason: 'the crop must land in the injected temp dir');
      final cropped = img.decodeImage(File(out).readAsBytesSync())!;
      expect(cropped.width, 348); // 696 * 0.5
      expect(cropped.height, 1000); // 2000 * 0.5
    });

    test('leaves the source file untouched', () async {
      final before = File(sourcePath).lengthSync();
      await service.crop(sourcePath,
          const CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9));
      expect(File(sourcePath).lengthSync(), before);
    });

    test('returns the source path unchanged when nothing is cropped',
        () async {
      final out = await service.crop(sourcePath, CropRect.full);

      expect(out, sourcePath);
      expect(tempDir.listSync(), isEmpty,
          reason: 'no re-encode means no new file and no quality loss');
    });

    test('normalizes the rect before cropping', () async {
      final out = await service.crop(sourcePath,
          const CropRect(left: 0.75, top: 1, right: 0.25, bottom: 0.5));

      final cropped = img.decodeImage(File(out).readAsBytesSync())!;
      expect(cropped.width, 348);
      expect(cropped.height, 1000);
    });

    test('rejects a file that is not an image', () async {
      final bogus = File('${tempDir.path}/not_an_image.jpg')
        ..writeAsStringSync('nope');
      expect(
          () => service.crop(bogus.path,
              const CropRect(left: 0, top: 0, right: 0.5, bottom: 0.5)),
          throwsA(isA<FormatException>()));
    });
  });

  group('CropService.sizeOf', () {
    test('reports the pixel size of a real receipt', () async {
      expect(await service.sizeOf(sourcePath), (696, 2000));
    });
  });
}
