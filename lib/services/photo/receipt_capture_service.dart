import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around the native capture paths. Returns the local path of
/// the captured image, or null when the user cancels.
///
/// Main path: ML Kit Document Scanner (Play Services UI, automatic
/// detection/crop/deskew, no in-app camera permission). Fallback path:
/// image_picker (scanner API is beta — docs/catena-detection-ocr.md).
///
/// [NON-BLOCKING] Hook point for the contrast/brightness plugin (v1.1):
/// post-process the returned path before handing it to PhotoService.
///
/// Methods are instance methods so widget tests can inject a subclass fake;
/// the real calls only run on-device (not verifiable on this machine —
/// verify at the first device build, see gotcha in CLAUDE.md).
class ReceiptCaptureService {
  DocumentScanner? _scanner;

  Future<String?> scanWithDocumentScanner() async {
    final scanner = _scanner ??= DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        mode: ScannerMode.filter,
        pageLimit: 1,
        isGalleryImport: true,
      ),
    );
    final result = await scanner.scanDocument();
    final images = result.images;
    return (images == null || images.isEmpty) ? null : images.first;
  }

  Future<String?> pickFromCamera() async =>
      (await ImagePicker().pickImage(source: ImageSource.camera))?.path;

  Future<String?> pickFromGallery() async =>
      (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;

  Future<void> dispose() async => _scanner?.close();
}
