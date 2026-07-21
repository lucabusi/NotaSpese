import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:nota_spese/ui/foto/crop_screen.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String imagePath;
  late CropService service;

  // Real IO in the body of testWidgets never completes (FakeAsync), so the
  // image is written here.
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crop_screen_test');
    imagePath = p.join(tempDir.path, 'scontrino.jpg');
    final im = img.Image(width: 400, height: 800);
    img.fill(im, color: img.ColorRgb8(200, 200, 200));
    File(imagePath).writeAsBytesSync(img.encodeJpg(im, quality: 95));
    service = CropService(tempDirProvider: () async => tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps the handle of a displayed Image.file open.
    }
  });

  Future<String?> pumpScreen(WidgetTester tester) async {
    String? result;
    var popped = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: CropScreen(
            imagePath: imagePath,
            imageWidth: 400,
            imageHeight: 800,
            cropService: service,
          ),
        ),
      ),
      navigatorObservers: [
        _PopObserver((value) {
          result = value as String?;
          popped = true;
        }),
      ],
    ));
    await tester.pump();
    return popped ? result : null;
  }

  // CropService.crop() chains three real IO awaits (readAsBytes ->
  // parent.create -> writeAsBytes). A single runAsync(tap) only gives the
  // chain one real-time escape, enough for a one-step IO call but not for a
  // sequential three-step one: bare pumpAndSettle() afterwards observes zero
  // written files, deterministically, because pumpAndSettle stops pumping as
  // soon as no frame is scheduled and no further real wall-clock time is
  // handed to the pending chain. This is the same class of gotcha already
  // solved in trasferta_detail_screen_test.dart's settleWithRealIo: give the
  // background IO repeated real-time slices, flushing after each one.
  Future<void> settleWithRealIo(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows the image to crop', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('crop-immagine')), findsOneWidget);
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
    expect(find.byKey(const Key('crop-annulla')), findsOneWidget);
  });

  testWidgets('confirming without dragging returns the source path untouched',
      (tester) async {
    await pumpScreen(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('crop-conferma')));
    });
    await tester.pumpAndSettle();

    // The rect still covers the whole image, so CropService short-circuits.
    expect(tempDir.listSync().whereType<File>().length, 1,
        reason: 'only the source image: nothing new was written');
  });

  testWidgets('dragging a corner handle shrinks the crop', (tester) async {
    await pumpScreen(tester);

    final before = tester.getRect(find.byKey(const Key('crop-riquadro')));
    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(40, 60));
    await tester.pump();
    final after = tester.getRect(find.byKey(const Key('crop-riquadro')));

    expect(after.width, lessThan(before.width));
    expect(after.height, lessThan(before.height));
    expect(after.left, greaterThan(before.left));
    expect(after.top, greaterThan(before.top));
  });

  testWidgets('after dragging, confirm writes a smaller image',
      (tester) async {
    await pumpScreen(tester);

    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(40, 60));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-conferma')));
    await settleWithRealIo(tester);

    final written = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('CROP_'))
        .toList();
    expect(written, hasLength(1));
    final cropped = img.decodeImage(written.single.readAsBytesSync())!;
    expect(cropped.width, lessThan(400));
    expect(cropped.height, lessThan(800));
  });

  testWidgets('cancel writes nothing', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('crop-annulla')));
    await tester.pumpAndSettle();

    expect(tempDir.listSync().whereType<File>().length, 1);
  });
}

class _PopObserver extends NavigatorObserver {
  _PopObserver(this.onPop);

  final void Function(Object?) onPop;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPop(route.currentResult);
    super.didPop(route, previousRoute);
  }
}
