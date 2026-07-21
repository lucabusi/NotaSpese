# Ritaglio dello scontrino dopo lo scatto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dopo lo scatto, prima dell'OCR e del salvataggio, l'utente ritaglia lo scontrino in una schermata in-app.

**Architecture:** Un servizio puro Dart (`CropService` + `CropRect` in frazioni 0..1) sopra il pacchetto `image` già usato da `PhotoService`, e una schermata Flutter che manipola il rettangolo in coordinate di schermo e converte in frazioni solo alla conferma. Nessuna dipendenza nativa nuova: la build Android non è verificabile su questa macchina, quindi tutto deve essere provabile su host.

**Tech Stack:** Flutter, Dart, pacchetto `image`, `flutter_test`.

Spec di riferimento: `docs/superpowers/specs/2026-07-21-crop-scontrino-design.md`

## Global Constraints

- Lingua: codice, identificatori e commenti in inglese; stringhe UI in italiano (termini di dominio italiani negli identificatori — `spesa`, `valuta`, `trasferta` — sono la convenzione esistente).
- `flutter analyze` a zero issue e `flutter test` verde alla fine di ogni task.
- Nessuna dipendenza nuova in `pubspec.yaml`. Nessuna modifica ai file Android.
- Nessuna migrazione DB.
- Non eseguire `dart format`: il repo non è dart-format pulito e riformattare seppellirebbe le modifiche.
- Asserzioni su stringhe che compaiono più volte: `findsNWidgets(n)`, mai `findsWidgets`.
- Bump di versione una sola volta, nell'ultimo task. Versione target: **0.9.0+11**.
- **Commit:** l'utente ha autorizzato un commit per task, direttamente su `main` (2026-07-21). Nessun push. Mai `--force`, `reset --hard`, `--no-verify`.
- **Gotcha dei widget test in questo repo** (già costati debug, rispettarli):
  - L'IO reale (`File`/`Directory`) nel corpo di `testWidgets` non completa mai (FakeAsync): preparare i file in `setUp`; l'IO innescato da un tap va avvolto in `tester.runAsync(...)` seguito da `pump()`.
  - Widget test col DB: `databaseFactoryFfiNoIsolate`, mai `databaseFactoryFfi`.
  - Su Windows `Image.file` tiene l'handle aperto: un file mostrato non è sempre cancellabile.
- Immagini reali disponibili e versionate: `scontrini_training/scontrino_JP_01.jpg` è **696x2000**, `scontrino_JP_02.jpg` è **591x2000**.

---

## File Structure

| File | Responsabilità | Azione |
|---|---|---|
| `lib/services/photo/crop_service.dart` | `CropRect` (frazioni + normalizzazione) e ritaglio su file | nuovo |
| `lib/ui/foto/crop_screen.dart` | schermata di ritaglio (rettangolo, maniglie, conferma) | nuovo |
| `lib/ui/trasferte/trasferta_detail_screen.dart` | aggancio nel flusso "scatta scontrino" | modifica |
| `test/crop_service_test.dart` | unit su `CropRect` e `CropService` | nuovo |
| `test/crop_screen_test.dart` | widget test della schermata | nuovo |
| `test/trasferta_detail_screen_test.dart` | il flusso scatta passa dal crop | modifica |

---

### Task 1: CropRect e CropService

**Files:**
- Create: `lib/services/photo/crop_service.dart`
- Test: `test/crop_service_test.dart`

**Interfaces:**
- Consumes: pacchetto `image` (`img.decodeImage`, `img.copyCrop`, `img.encodeJpg`), `path`.
- Produces:
  - `class CropRect` — campi `double left, top, right, bottom` (frazioni 0..1), `static const CropRect full`, `static const double minSide = 0.05`, `double get width`, `double get height`, `bool get isFull`, `CropRect clamped()`, `operator ==`/`hashCode`/`toString`.
  - `class CropService` — `CropService({Future<String> Function()? tempDirProvider})`, `Future<String> crop(String sourcePath, CropRect rect)`, `Future<(int, int)> sizeOf(String sourcePath)`.

- [ ] **Step 1: Write the failing test**

Crea `test/crop_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/services/photo/crop_service.dart';

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
```

Aggiungi in cima anche `import 'package:path/path.dart' as p;` (serve a `p.isWithin`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crop_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/services/photo/crop_service.dart'`.

- [ ] **Step 3: Write minimal implementation**

Crea `lib/services/photo/crop_service.dart`:

```dart
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
    final x = (safe.left * decoded.width).round();
    final y = (safe.top * decoded.height).round();
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

  Future<img.Image> _decode(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw FormatException('Immagine non valida: $sourcePath');
    }
    return decoded;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/crop_service_test.dart`
Expected: PASS.
Poi `flutter test` (suite completa) e `flutter analyze` → verdi.

- [ ] **Step 5: Commit**

```bash
git add lib/services/photo/crop_service.dart test/crop_service_test.dart
git commit -m "feat: crop service for captured receipts"
```

---

### Task 2: Schermata di ritaglio

**Files:**
- Create: `lib/ui/foto/crop_screen.dart`
- Test: `test/crop_screen_test.dart`

**Interfaces:**
- Consumes: `CropRect`, `CropService` (Task 1); `AppColors` da `lib/core/theme/app_theme.dart`.
- Produces: `class CropScreen extends StatefulWidget` con costruttore `CropScreen({super.key, required String imagePath, required int imageWidth, required int imageHeight, required CropService cropService})` e
  `static Future<String?> show(BuildContext context, {required String imagePath, required CropService cropService})` — legge la dimensione con `cropService.sizeOf` **prima** di fare push, così il widget non fa IO in `build`/`initState` (gotcha FakeAsync dei widget test).

Chiavi per i test: `Key('crop-immagine')`, `Key('crop-handle-tl')`, `Key('crop-handle-tr')`, `Key('crop-handle-bl')`, `Key('crop-handle-br')`, `Key('crop-conferma')`, `Key('crop-annulla')`.

- [ ] **Step 1: Write the failing test**

Crea `test/crop_screen_test.dart`:

```dart
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
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('crop-conferma')));
    });
    await tester.pumpAndSettle();

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
```

Nota per l'implementatore: il widget del rettangolo deve avere `Key('crop-riquadro')` perché i test ne misurino la geometria con `tester.getRect`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crop_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nota_spese/ui/foto/crop_screen.dart'`.

- [ ] **Step 3: Write minimal implementation**

Crea `lib/ui/foto/crop_screen.dart`. Struttura richiesta:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

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
```

Requisiti dello stato e del layout:

- `Rect? _rect` in coordinate del box visualizzato; alla prima `LayoutBuilder` vale l'intero box.
- L'immagine sta dentro `Center` → `AspectRatio(aspectRatio: imageWidth / imageHeight)` → `LayoutBuilder`: così il box **coincide** con l'immagine mostrata e la conversione box→frazioni è una divisione, senza lettere piccole su `BoxFit`.
- Dentro uno `Stack`: `Positioned.fill` con `Image.file(File(widget.imagePath), fit: BoxFit.fill, key: const Key('crop-immagine'))`; l'area esterna al rettangolo oscurata (`Container(color: Colors.black54)` a fasce, o un `CustomPaint`); il rettangolo con `Key('crop-riquadro')` e un bordo visibile; quattro maniglie d'angolo di almeno 44x44 con le chiavi indicate, ciascuna con `GestureDetector(onPanUpdate:)` che sposta il proprio angolo.
- Ogni aggiornamento tiene il rettangolo dentro il box e non sotto `CropRect.minSide` sui due lati (riusa `CropRect(...).clamped()` convertendo in frazioni, oppure applica il minimo in pixel derivandolo dal box: una sola regola, non due).
- `AppBar` con `Key('crop-annulla')` come `leading` (icona chiudi, `Navigator.pop(context)` senza valore) e un `TextButton`/`IconButton` `Key('crop-conferma')` fra le azioni. Titolo: `Ritaglia scontrino`.
- Conferma: converte `_rect` in `CropRect` dividendo per la dimensione del box, chiama `widget.cropService.crop(...)` e fa `Navigator.pop(context, risultato)`; guardia `mounted` dopo l'await.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/crop_screen_test.dart`
Expected: PASS.
Poi `flutter test` e `flutter analyze` → verdi.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/foto/crop_screen.dart test/crop_screen_test.dart
git commit -m "feat: in-app crop screen for captured receipts"
```

---

### Task 3: Aggancio nel flusso "scatta scontrino"

**Files:**
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart` (costruttore dello screen + `_scattaEOcr`, attorno alle righe 204-234)
- Test: `test/trasferta_detail_screen_test.dart`

**Interfaces:**
- Consumes: `CropScreen.show` (Task 2), `CropService` (Task 1).
- Produces: `TrasfertaDetailScreen` guadagna il parametro opzionale `CropService? cropService`; quando è null lo screen ne costruisce uno proprio (`CropService()`), così nessun chiamante esistente (`trasferte_list_screen.dart`, `main.dart`, i loro test) va toccato. `CropService` è puro Dart e non ha bisogno di fake nei test.

- [ ] **Step 1: Write the failing test**

In `test/trasferta_detail_screen_test.dart`, il test esistente che copre il flusso di scatto (`photo flow: scatta → form preview → …`) ora deve passare per il ritaglio. Aggiungi accanto a quello:

```dart
  testWidgets('scatta: il crop precede l\'OCR e ne riceve il ritaglio',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await tester.pumpAndSettle();

    // Crop screen instead of going straight to the OCR.
    expect(find.byKey(const Key('crop-conferma')), findsOneWidget);
    expect(orchestrator.calls, isEmpty);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('crop-conferma')));
    });
    await tester.pumpAndSettle();

    expect(orchestrator.calls, hasLength(1));
    expect(find.text('Nuova spesa'), findsOneWidget);
  });

  testWidgets('scatta: annullare il crop non lancia l\'OCR', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-scatta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-annulla')));
    await tester.pumpAndSettle();

    expect(orchestrator.calls, isEmpty);
    expect(find.text('Nuova spesa'), findsNothing);
    expect(find.text('Tokyo'), findsOneWidget); // back on the detail screen
  });
```

Adatta i nomi (`orchestrator`, `pump`, la chiave del tile "scatta") a quelli realmente usati nel file: il fake orchestrator vi registra già le chiamate in una lista `calls`, e `_FakeCaptureService` restituisce un jpg preparato in `setUp`. Se il fake capture service non è già configurato con un'immagine reale decodificabile, rendilo tale (serve a `CropService.sizeOf`).

Il test preesistente del flusso foto va aggiornato per confermare il crop prima di aspettarsi il form.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/trasferta_detail_screen_test.dart --plain-name "il crop precede"`
Expected: FAIL — nessun `crop-conferma` sullo schermo, l'OCR è già stato invocato.

- [ ] **Step 3: Write minimal implementation**

Nel costruttore di `TrasfertaDetailScreen` aggiungi `this.cropService` (opzionale, `final CropService? cropService;`) e nello stato:

```dart
  late final CropService _cropService = widget.cropService ?? CropService();
```

In `_scattaEOcr`, subito dopo la cattura:

```dart
  Future<void> _scattaEOcr(OcrEngine engine) async {
    final path = await _captureScatta();
    if (path == null || !mounted) return;
    // Crop before anything else: the recognized text and the saved photo
    // must describe the same framing.
    final ritagliata = await CropScreen.show(context,
        imagePath: path, cropService: _cropService);
    if (ritagliata == null || !mounted) return;
    final t = controller.trasferta;
    final result = await showOcrProgress(
      context,
      widget.orchestrator.recognize(ritagliata,
          engine: engine,
          linguaHint:
              effectiveLinguaHint(t?.linguaDefault, t?.valutaDefault)),
    );
    if (result == null || !mounted) return;
    _showFallbackSnackbarIfNeeded(result);
    _showCyrillicSnackbarIfNeeded(result, t);
    await _openSpesaForm(
      pendingFoto: ritagliata,
      parsed: result.receipt,
      onRetryOtherEngine:
          _makeRetryCallback(ritagliata, result.receipt.engine, t),
    );
  }
```

`path` non deve più comparire dopo questa riga: OCR, `pendingFoto` e callback di retry usano tutti `ritagliata`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trasferta_detail_screen_test.dart`
Expected: PASS, incluso il test preesistente del flusso foto (aggiornato).
Poi `flutter test` e `flutter analyze` → verdi.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/trasferte/trasferta_detail_screen.dart test/trasferta_detail_screen_test.dart
git commit -m "feat: crop the receipt between capture and OCR"
```

---

### Task 4: Verifica finale, versione, ToDo

**Files:**
- Modify: `lib/version.dart`, `pubspec.yaml`, `ToDo.md`

- [ ] **Step 1: Suite completa**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Bump versione**

`lib/version.dart` → `const String appVersion = '0.9.0';`
`pubspec.yaml` → `version: 0.9.0+11`

- [ ] **Step 4: Aggiorna `ToDo.md`**

Nella fase 4 (foto scontrino) c'è una voce sul ritaglio rimandata al dispositivo reale: verificala e allineala. Aggiungi inoltre, nella sezione della fase 6b, sotto le voci BUG:

```markdown
- [x] **Ritaglio dopo lo scatto** (2026-07-21, v0.9.0): schermata di crop in-app tra cattura e OCR (`lib/ui/foto/crop_screen.dart` + `lib/services/photo/crop_service.dart`, Dart puro sopra il pacchetto `image`, nessuna dipendenza nativa). Il rettangolo parte sull'immagine intera: confermare senza trascinare non ricodifica il file. Il ritaglio vale sia per il testo passato all'OCR sia per la foto salvata. Spec: `docs/superpowers/specs/2026-07-21-crop-scontrino-design.md`.
```

- [ ] **Step 5: Rerun della suite dopo il bump**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/version.dart pubspec.yaml ToDo.md
git commit -m "chore: bump to 0.9.0, receipt crop step"
```

---

## Verifica di fase (CLAUDE.md)

- [ ] `flutter analyze` → zero issue
- [ ] `flutter test` → verde
- [ ] Build su emulatore: **SKIP esplicito** — ambiente Android incompleto su questa macchina. Nessun file Android toccato da questo piano, quindi il rischio di regressione di build è nullo.
- [ ] Verifica manuale sul dispositivo: scattare uno scontrino, ritagliarlo, controllare che il testo riconosciuto e la foto salvata corrispondano al ritaglio.
- [ ] `ToDo.md` aggiornato (Task 4)
