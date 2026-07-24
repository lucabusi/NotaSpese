import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/pdf_export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';

Trasferta _trip() => Trasferta(
      id: 1,
      nome: 'Tokyo',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 1),
      dataFine: DateTime(2026, 7, 5),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

Spesa _spesa({int? id, String? fornitore, double importo = 1000}) => Spesa(
      id: id,
      trasfertaId: 1,
      data: DateTime(2026, 7, 2),
      categoria: Categoria.pranzo,
      fornitore: fornitore,
      importo: importo,
      valuta: 'JPY',
      importoEur: 6.5,
      createdAt: DateTime(2026, 7, 2),
    );

Uint8List _jpg() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfFonts fonts;
  setUpAll(() async {
    fonts = await PdfFonts.load();
  });

  test('produces non-empty bytes without photos', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 1)]),
      fotoBytesBySpesaId: const {},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('produces non-empty bytes with a photo', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 7)]),
      fotoBytesBySpesaId: {7: _jpg()},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('renders a Japanese vendor name without throwing', () async {
    final bytes = await const PdfExportService().build(
      TrasfertaReport.build(_trip(), [_spesa(id: 1, fornitore: 'スターバックス')]),
      fotoBytesBySpesaId: const {},
      fonts: fonts,
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });
}
