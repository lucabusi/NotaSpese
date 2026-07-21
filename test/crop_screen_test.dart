import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/services/photo/crop_service.dart';
import 'package:nota_spese/ui/foto/crop_screen.dart';
import 'package:path/path.dart' as p;

/// CropService whose sizeOf/crop can be overridden to fail or hang, so the
/// error-handling and re-entrancy paths of CropScreen are testable without
/// needing a real broken file or a real multi-second crop.
class _FakeCropService extends CropService {
  _FakeCropService({this.sizeOfImpl, this.cropImpl})
      : super(tempDirProvider: () async => Directory.systemTemp.path);

  Future<(int, int)> Function(String sourcePath)? sizeOfImpl;
  Future<String> Function(String sourcePath, CropRect rect)? cropImpl;
  int cropCalls = 0;

  @override
  Future<(int, int)> sizeOf(String sourcePath) =>
      sizeOfImpl?.call(sourcePath) ?? super.sizeOf(sourcePath);

  @override
  Future<String> crop(String sourcePath, CropRect rect) {
    cropCalls++;
    return cropImpl?.call(sourcePath, rect) ?? super.crop(sourcePath, rect);
  }
}

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

  // Pushes CropScreen as a real route (rather than as the MaterialApp home)
  // so Navigator.pop has something to pop. [popped] collects the pushed
  // route's result once it completes — NOT via NavigatorObserver's
  // `route.currentResult`, which is a base Route getter that always
  // returns null in this SDK unless a subclass overrides it (none do for
  // MaterialPageRoute): the only reliable signal is the Future that
  // Navigator.push itself returns.
  Future<void> pushCropScreen(
    WidgetTester tester, {
    CropService? cropService,
    required List<String?> popped,
  }) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator
        .push(MaterialPageRoute<String>(
          builder: (_) => CropScreen(
            imagePath: imagePath,
            imageWidth: 400,
            imageHeight: 800,
            cropService: cropService ?? service,
          ),
        ))
        .then((value) => popped.add(value)));
    await tester.pumpAndSettle();
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
    await pushCropScreen(tester, popped: []);

    expect(find.byKey(const Key('crop-immagine')), findsOneWidget);
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
    expect(find.byKey(const Key('crop-annulla')), findsOneWidget);
  });

  testWidgets('confirming without dragging returns the source path untouched',
      (tester) async {
    final popped = <String?>[];
    await pushCropScreen(tester, popped: popped);

    await tester.tap(find.byKey(const Key('crop-conferma')));
    await settleWithRealIo(tester);

    // The rect still covers the whole image, so CropService short-circuits:
    // no new file, and the popped value is the untouched source path.
    expect(tempDir.listSync().whereType<File>().length, 1,
        reason: 'only the source image: nothing new was written');
    expect(popped, [imagePath]);
  });

  testWidgets('dragging a corner handle shrinks the crop', (tester) async {
    await pushCropScreen(tester, popped: []);

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

  testWidgets(
      'corner handles stay fully inside the box even at the initial '
      'full-image rect', (tester) async {
    await pushCropScreen(tester, popped: []);

    final box = tester.getRect(find.byType(AspectRatio));
    for (final suffix in ['tl', 'tr', 'bl', 'br']) {
      final handle = tester.getRect(find.byKey(Key('crop-handle-$suffix')));
      expect(handle.left, greaterThanOrEqualTo(box.left - 0.01),
          reason: 'handle $suffix must not spill past the box (and its '
              'hard clip) on the left');
      expect(handle.top, greaterThanOrEqualTo(box.top - 0.01),
          reason: 'handle $suffix must not spill past the box on top');
      expect(handle.right, lessThanOrEqualTo(box.right + 0.01),
          reason: 'handle $suffix must not spill past the box on the '
              'right');
      expect(handle.bottom, lessThanOrEqualTo(box.bottom + 0.01),
          reason: 'handle $suffix must not spill past the box on the '
              'bottom');
    }
  });

  testWidgets('dragging the crop body translates it without resizing',
      (tester) async {
    await pushCropScreen(tester, popped: []);

    // Shrink via the top-left handle: right/bottom stay pinned to the box
    // edge (1.0), left/top move inward — so there is slack to translate
    // the body back toward the top-left, but none toward the bottom-right.
    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(80, 80));
    await tester.pump();
    final before = tester.getRect(find.byKey(const Key('crop-riquadro')));

    await tester.drag(
        find.byKey(const Key('crop-corpo')), const Offset(-30, -20));
    await tester.pump();
    final after = tester.getRect(find.byKey(const Key('crop-riquadro')));

    expect(after.width, closeTo(before.width, 0.5));
    expect(after.height, closeTo(before.height, 0.5));
    expect(after.left, lessThan(before.left));
    expect(after.top, lessThan(before.top));
  });

  testWidgets(
      'rotating the device (a box-size change) keeps the crop as the same '
      'fraction of the box, with handles still in bounds', (tester) async {
    await pushCropScreen(tester, popped: []);

    await tester.drag(
        find.byKey(const Key('crop-handle-tl')), const Offset(80, 120));
    await tester.pump();

    Rect fractionOf(Rect box, Rect r) => Rect.fromLTRB(
          (r.left - box.left) / box.width,
          (r.top - box.top) / box.height,
          (r.right - box.left) / box.width,
          (r.bottom - box.top) / box.height,
        );

    final boxBefore = tester.getRect(find.byType(AspectRatio));
    final cropBefore = tester.getRect(find.byKey(const Key('crop-riquadro')));
    final fractionBefore = fractionOf(boxBefore, cropBefore);

    // Simulate a rotation: the available space changes shape (portrait ->
    // landscape-ish), so the AspectRatio box is laid out with a different
    // size than the one the drag above happened in.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400));
    await tester.pumpAndSettle();

    final boxAfter = tester.getRect(find.byType(AspectRatio));
    final cropAfter = tester.getRect(find.byKey(const Key('crop-riquadro')));
    final fractionAfter = fractionOf(boxAfter, cropAfter);

    expect(fractionAfter.left, closeTo(fractionBefore.left, 0.01));
    expect(fractionAfter.top, closeTo(fractionBefore.top, 0.01));
    expect(fractionAfter.right, closeTo(fractionBefore.right, 0.01));
    expect(fractionAfter.bottom, closeTo(fractionBefore.bottom, 0.01));

    for (final suffix in ['tl', 'tr', 'bl', 'br']) {
      final handle =
          tester.getRect(find.byKey(Key('crop-handle-$suffix')));
      expect(boxAfter.overlaps(handle), isTrue,
          reason: 'handle $suffix must still land near the (resized) box, '
              'not off in stale pixel coordinates');
    }
  });

  testWidgets('after dragging, confirm writes a smaller image and pops with '
      'its path', (tester) async {
    final popped = <String?>[];
    await pushCropScreen(tester, popped: popped);

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
    expect(popped, [written.single.path]);
  });

  testWidgets('cancel writes nothing and pops with no value', (tester) async {
    final popped = <String?>[];
    await pushCropScreen(tester, popped: popped);

    await tester.tap(find.byKey(const Key('crop-annulla')));
    await tester.pumpAndSettle();

    expect(tempDir.listSync().whereType<File>().length, 1);
    expect(popped, [null]);
  });

  testWidgets(
      'a CropService that throws on crop shows a snackbar and never pops',
      (tester) async {
    final failing = _FakeCropService(
        cropImpl: (_, _) async => throw const FormatException('corrupt'));
    final popped = <String?>[];
    await pushCropScreen(tester, cropService: failing, popped: popped);

    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pumpAndSettle();

    expect(find.text('Immagine non leggibile'), findsOneWidget);
    expect(popped, isEmpty,
        reason: 'a failed crop must leave the user on the crop screen, '
            'not pop with a null/garbage value');
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
  });

  testWidgets(
      'a second tap while a crop is in flight does not queue a second crop '
      'or a second pop', (tester) async {
    final completer = Completer<String>();
    final slow = _FakeCropService(cropImpl: (_, _) => completer.future);
    final popped = <String?>[];
    await pushCropScreen(tester, cropService: slow, popped: popped);

    await tester.tap(find.byKey(const Key('crop-conferma')));
    await tester.pump();
    // The blocking progress dialog already covers the button by now, so
    // this second tap mostly exercises that barrier rather than the
    // `_confirming` guard — but either way it must not reach a second
    // crop. warnIfMissed: false because "the tap didn't hit the button" is
    // exactly the (acceptable) outcome here, not a broken finder.
    await tester.tap(find.byKey(const Key('crop-conferma')),
        warnIfMissed: false);
    await tester.pump();

    expect(slow.cropCalls, 1,
        reason: 'the second tap must be ignored while the first is still '
            'running');

    completer.complete(imagePath);
    await tester.pumpAndSettle();

    expect(popped, [imagePath],
        reason: 'exactly one pop, from the single crop that actually ran');
  });

  testWidgets(
      'CropScreen.show: a CropService that throws on sizeOf shows a '
      'snackbar and never pushes the crop screen', (tester) async {
    final failing = _FakeCropService(
        sizeOfImpl: (_) async => throw const FormatException('corrupt'));
    String? result;
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            key: const Key('apri-crop'),
            onPressed: () async {
              result = await CropScreen.show(context,
                  imagePath: imagePath, cropService: failing);
              called = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('apri-crop')));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
    expect(find.text('Immagine non leggibile'), findsOneWidget);
    expect(find.byKey(const Key('crop-conferma')), findsNothing);
  });
}
