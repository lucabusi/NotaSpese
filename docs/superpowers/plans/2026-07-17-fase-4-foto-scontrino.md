# Fase 4 — Foto scontrino Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pipeline foto completa: scatto (ML Kit Document Scanner / image_picker), compressione JPG + thumbnail, foto allegata alla spesa (form + lista), viewer fullscreen, eliminazione coerente file+record.

**Architecture:** Due nuovi service (`SettingsService` minimale su SharedPreferences, `PhotoService` filesystem-only con package `image` pure Dart) + un wrapper nativo sottile (`ReceiptCaptureService`, non testabile su host). `TrasfertaDetailController` diventa foto-aware (attach/replace/remove + mappa thumb per la lista). Composizione manuale invariata: i nuovi oggetti scendono da `main.dart` lungo la catena esistente.

**Tech Stack:** `shared_preferences`, `image` (pure Dart), `google_mlkit_document_scanner`, `image_picker`, `share_plus`.

## Global Constraints

- UI in italiano; codice/commit/identificatori in inglese. Mai sqflite/filesystem dai controller: repository/service.
- Widget test col DB: `databaseFactoryFfiNoIsolate`. Scroll nei form: `scrollUntilVisible` con Scrollable esplicito della ListView (gotcha fase 3).
- Path foto in DB **relativi** alla directory foto, separatore **`/`** (mai `p.join` per il path salvato: su Windows produrrebbe `\`).
- Ordine eliminazione: file fisici PRIMA dei record (già nei repository).
- Verifica fase: `flutter analyze` zero issue + `flutter test` verde; emulatore/camera = SKIP esplicito (gotcha ambiente), da verificare appena l'ambiente è completo.
- Bump a fine fase: `pubspec.yaml` `0.5.0+5` + `lib/version.dart` `'0.5.0'`.

## Deviazioni dalla spec (decise in pianificazione, da riportare in Specifiche.md al Task 8)

- `flutter_image_compress` → **`image`** (pure Dart): unit test reali su host senza device; volume foto minimo rende irrilevante la differenza di velocità.
- **`permission_handler` non necessario in v1.0**: scanner = UI Play Services (no permesso in-app); `image_picker` gestisce CAMERA a runtime; photo picker di sistema senza `READ_MEDIA_IMAGES`. I permessi restano dichiarati nel manifest (ToDo).
- **`image_cropper` rimandato** (era "✎ Edit" opzionale): lo scanner croppa/deskewa già; aggancio previsto nel flusso.
- **`share_plus` anticipato** dalla fase 7 per lo share del viewer.

## File Structure

- Modify: `pubspec.yaml` (deps), `android/app/src/main/AndroidManifest.xml` (permessi)
- Create: `lib/services/settings/settings_service.dart`
- Create: `lib/services/photo/photo_service.dart` (+ `PhotoPaths`)
- Create: `lib/services/photo/receipt_capture_service.dart`
- Create: `lib/ui/foto/photo_viewer_screen.dart`
- Modify: `lib/data/repositories/foto_repository.dart` (+`getByTrasferta`)
- Modify: `lib/ui/trasferte/trasferta_detail_controller.dart` (foto-aware)
- Modify: `lib/ui/spese/spesa_form_screen.dart` (sezione foto)
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart`, `lib/ui/trasferte/trasferte_list_screen.dart`, `lib/ui/shell/home_shell.dart`, `lib/app.dart`, `lib/main.dart` (plumbing)
- Test: `test/settings_service_test.dart`, `test/photo_service_test.dart`; Modify: `test/trasferta_detail_controller_test.dart`, `test/spesa_form_screen_test.dart`, `test/trasferta_detail_screen_test.dart`, `test/trasferte_list_screen_test.dart`, `test/home_shell_test.dart`, `test/widget_test.dart`

---

### Task 1: Dipendenze + permessi manifest

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1:** `flutter pub add shared_preferences image google_mlkit_document_scanner image_picker share_plus`
- [ ] **Step 2:** In `AndroidManifest.xml`, prima di `<application`:

```xml
    <!-- Fase 4: camera per il percorso di riserva image_picker; media per
         eventuale import galleria pre-photo-picker (ToDo §Fase 4). -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

- [ ] **Step 3:** `flutter analyze` → zero issue; `flutter test` → suite fase 1-3 ancora verde.

### Task 2: SettingsService minimale (TDD)

**Produces:** `class SettingsService` con `Future<int> get jpgQuality` (default 70), `Future<void> setJpgQuality(int)` (clamp 50-90), `Future<PhotoDirKind> get photoDirKind` (default `internal`), `Future<void> setPhotoDirKind(PhotoDirKind)`; `enum PhotoDirKind { internal, external }`.

Test (`test/settings_service_test.dart`) con `SharedPreferences.setMockInitialValues({})`: default 70/internal; set→get persiste; clamp fuori range.

### Task 3: PhotoService (TDD)

**Produces:** `class PhotoService { PhotoService(SettingsService settings, {required Future<String> Function() basePathProvider}); Future<PhotoPaths> process(String sourcePath); Future<String> absolutePath(String relative); static const int maxLongSide = 1920; static const int thumbSize = 300; }` e `class PhotoPaths { final String filePath; final String thumbPath; }` (path **relativi**, thumb in `thumbnails/`, separatore `/`).

Regole: decode → resize lato lungo max 1920 (mai upscale) → JPG qualità da settings → `IMG_<epoch_ms>.jpg`; thumb 300px `thumbnails/IMG_<epoch_ms>_thumb.jpg`; sorgente non toccata (il chiamante può eliminarla).

Test (`test/photo_service_test.dart`): immagine sintetica 3000×2000 (package `image`) su temp dir → process → file esistono, decodifica 1920×1280 e thumb 300×200, path relativi con `/`, immagine piccola non upscalata.

### Task 4: ReceiptCaptureService (nativo, niente test host)

**Produces:** `class ReceiptCaptureService { Future<String?> scanWithDocumentScanner(); Future<String?> pickFromCamera(); Future<String?> pickFromGallery(); Future<void> dispose(); }` — ritorna path locale o null se annullato. Scanner: `DocumentScannerOptions(documentFormat: jpeg, mode: filter, pageLimit: 1, isGalleryImport: true)`. `[NON-BLOCKING]` commento: aggancio plugin contrast/brightness v1.1; API scanner in beta → verificare al primo build su device. Metodi overridabili (i test iniettano una sottoclasse fake).

### Task 5: Controller foto-aware + FotoRepository.getByTrasferta (TDD)

**Produces:**
- `FotoRepository.getByTrasferta(int trasfertaId) → Future<List<Foto>>` (JOIN su spese).
- `TrasfertaDetailController(trasfertaId, trasfertaRepo, spesaRepo, fotoRepo, photoService)`; campo `Map<int, Foto> fotoBySpesa` (popolato in `load()`); `createSpesa(Spesa, {String? fotoSourcePath})`, `updateSpesa(Spesa, {String? fotoSourcePath, bool rimuoviFoto = false})` (nuova foto sostituisce l'esistente: delete file+record poi attach); `deleteSpesa` invariato (repo elimina già file+record).

Test controller: create con foto → record foto + file su disco; update con rimuoviFoto → file spariti; delete spesa → file spariti; `fotoBySpesa` popolata.

### Task 6: Form spesa — sezione foto (TDD)

**Produces:** nuovi parametri `SpesaFormScreen`: `Foto? initialFoto`, `String? pendingFotoSourcePath`, `Future<String?> Function()? onPickFoto`, `Future<String> Function(String rel)? photoPathResolver`; `onSave` diventa `Future<void> Function(Spesa spesa, {String? nuovaFoto, bool rimuoviFoto})`.

UI (dopo Note, prima di Salva): pending → preview `Image.file` + `Key('foto-rimuovi')`; foto esistente (non rimossa) → thumb via resolver, tap → `PhotoViewerScreen`, pulsante rimuovi; nessuna → area `Key('foto-area-aggiungi')` "Aggiungi foto" → `onPickFoto`. Stato: `_fotoSource`, `_rimuoviFoto`. Aggiornare i test esistenti alla nuova firma `onSave` + nuovi test (aggiungi da fake, preset pending, rimozione).

### Task 7: Integrazione — 📷 abilitato, plumbing, thumb in lista, viewer

**Produces:**
- `PhotoViewerScreen({required String imagePath, Future<void> Function()? onDelete})`: sfondo scuro (`AppColors.surfaceDark`), `InteractiveViewer` + `Image.file`, share (`Share.shareXFiles`), elimina con conferma → `onDelete` → pop.
- Detail screen: sheet 📷 abilitato → `scanWithDocumentScanner()` (catch → `pickFromCamera()`) → form con `pendingFotoSourcePath`; `onPickFoto` (bottom sheet scanner/camera/galleria) e `photoPathResolver` passati al form; tile spesa: thumb `Image.file` se `fotoBySpesa[spesa.id]` esiste, altrimenti icona categoria.
- Plumbing nuovi parametri (`fotoRepository`, `photoService`, `captureService`) lungo `main.dart` → `app.dart` → `home_shell.dart` → `trasferte_list_screen.dart` → detail; base dir foto = `<documents>/foto` (funzione unica condivisa da `FotoRepository` e `PhotoService`).
- Test aggiornati (costruttori) + widget test e2e: fake capture → 📷 → form con preview → salva → thumb in lista + file su disco → elimina spesa → file spariti.

### Task 8: Chiusura fase

- Bump `0.5.0+5` + `lib/version.dart`.
- `flutter analyze` zero issue + `flutter test` tutto verde.
- `ToDo.md` fase 4: spunte + SKIP espliciti (emulatore/camera, permessi runtime non verificabili) + note deviazioni (image, no permission_handler, image_cropper rimandato).
- `Specifiche.md`: tabella package aggiornata (`image` al posto di `flutter_image_compress`, nota permission_handler), §2 invariato.
- Memoria persistente aggiornata.
