import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/services/photo/photo_service.dart';
import 'package:nota_spese/services/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory baseDir;
  late Directory sourceDir;
  late PhotoService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    baseDir = await Directory.systemTemp.createTemp('foto_base');
    sourceDir = await Directory.systemTemp.createTemp('foto_src');
    service = PhotoService(SettingsService(),
        basePathProvider: () async => baseDir.path);
  });

  tearDown(() async {
    await baseDir.delete(recursive: true);
    await sourceDir.delete(recursive: true);
  });

  Future<String> writeSource(int width, int height) async {
    final im = img.Image(width: width, height: height);
    img.fill(im, color: img.ColorRgb8(200, 120, 40));
    final path = '${sourceDir.path}${Platform.pathSeparator}src.jpg';
    await File(path).writeAsBytes(img.encodeJpg(im, quality: 95));
    return path;
  }

  test('process resizes to 1920 long side and makes a 300px thumbnail',
      () async {
    final source = await writeSource(3000, 2000);

    final paths = await service.process(source);

    expect(paths.filePath, matches(r'^IMG_\d+\.jpg$'));
    expect(paths.thumbPath, matches(r'^thumbnails/IMG_\d+_thumb\.jpg$'));

    final file = File(await service.absolutePath(paths.filePath));
    final thumb = File(await service.absolutePath(paths.thumbPath));
    expect(file.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);

    final decoded = img.decodeImage(await file.readAsBytes())!;
    expect(decoded.width, 1920);
    expect(decoded.height, 1280);
    final decodedThumb = img.decodeImage(await thumb.readAsBytes())!;
    expect(decodedThumb.width, 300);
    expect(decodedThumb.height, 200);

    // La sorgente non viene toccata (la elimina il chiamante).
    expect(File(source).existsSync(), isTrue);
  });

  test('portrait images resize on height', () async {
    final source = await writeSource(1000, 4000);

    final paths = await service.process(source);
    final decoded =
        img.decodeImage(await File(await service.absolutePath(paths.filePath))
            .readAsBytes())!;
    expect(decoded.height, 1920);
    expect(decoded.width, 480);
  });

  test('small images are never upscaled', () async {
    final source = await writeSource(800, 600);

    final paths = await service.process(source);
    final decoded =
        img.decodeImage(await File(await service.absolutePath(paths.filePath))
            .readAsBytes())!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
  });

  test('invalid source throws FormatException', () async {
    final path = '${sourceDir.path}${Platform.pathSeparator}bad.jpg';
    await File(path).writeAsString('not an image');
    expect(() => service.process(path), throwsFormatException);
  });
}
