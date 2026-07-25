import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/trasferta.dart';
import 'csv_export_service.dart';
import 'export_file_name.dart';
import 'pdf_export_service.dart';
import 'trasferta_report.dart';

/// Turns a [TrasfertaReport] into a shared file. Renderers, temp dir, share
/// and font loading are injected so the whole flow is host-testable; the
/// defaults are the real Android implementations.
class ExportService {
  ExportService({
    PdfExportService pdf = const PdfExportService(),
    CsvExportService csv = const CsvExportService(),
    Future<Directory> Function()? tempDir,
    Future<void> Function(List<XFile>)? share,
    Future<PdfFonts> Function()? loadFonts,
  })  :
    // ignore: prefer_initializing_formals
    _pdf = pdf,
    // ignore: prefer_initializing_formals
    _csv = csv,
        _tempDir = tempDir ?? getTemporaryDirectory,
        _share = share ??
            ((files) => SharePlus.instance.share(ShareParams(files: files))),
        _loadFonts = loadFonts ?? PdfFonts.load;

  final PdfExportService _pdf;
  final CsvExportService _csv;
  final Future<Directory> Function() _tempDir;
  final Future<void> Function(List<XFile>) _share;
  final Future<PdfFonts> Function() _loadFonts;

  Future<void> exportCsv(TrasfertaReport report, Trasferta trasferta) async {
    final content = _csv.build(report);
    final file = await _tempFile(exportFileName(trasferta, 'csv'));
    await file.writeAsString(content);
    await _share([XFile(file.path)]);
  }

  Future<void> exportPdf(TrasfertaReport report, Trasferta trasferta,
      Map<int, Uint8List> fotoBytesBySpesaId) async {
    final fonts = await _loadFonts();
    final bytes = await _pdf.build(report,
        fotoBytesBySpesaId: fotoBytesBySpesaId, fonts: fonts);
    final file = await _tempFile(exportFileName(trasferta, 'pdf'));
    await file.writeAsBytes(bytes);
    await _share([XFile(file.path)]);
  }

  Future<File> _tempFile(String name) async =>
      File(p.join((await _tempDir()).path, name));
}
