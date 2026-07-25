import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';
import 'package:nota_spese/services/export/export_file_name.dart';
import 'package:nota_spese/services/export/export_service.dart';
import 'package:nota_spese/services/export/trasferta_report.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart'; // re-exports XFile

Trasferta _trip({String nome = 'Tokyo 2026'}) => Trasferta(
      id: 1,
      nome: nome,
      dataInizio: DateTime(2026, 7, 1),
      valutaDefault: 'JPY',
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  group('exportFileName', () {
    test('slugs the trip name and uses dataInizio year-month', () {
      expect(exportFileName(_trip(nome: 'Tokyo 2026'), 'csv'),
          'NotaSpese_Tokyo_2026_2026-07.csv');
    });

    test('strips unsafe characters and falls back when empty', () {
      expect(exportFileName(_trip(nome: 'Roma/Milano!'), 'pdf'),
          'NotaSpese_RomaMilano_2026-07.pdf');
      expect(exportFileName(_trip(nome: '***'), 'pdf'),
          'NotaSpese_trasferta_2026-07.pdf');
    });
  });

  test('exportCsv writes a BOM file to temp and shares it', () async {
    final dir = await Directory.systemTemp.createTemp('export_test');
    final shared = <XFile>[];
    final service = ExportService(
      tempDir: () async => dir,
      share: (files) async => shared.addAll(files),
    );
    final report = TrasfertaReport.build(_trip(), [
      Spesa(
        id: 1,
        trasfertaId: 1,
        data: DateTime(2026, 7, 2),
        categoria: Categoria.pranzo,
        importo: 10,
        valuta: 'EUR',
        importoEur: 10,
        createdAt: DateTime(2026, 7, 2),
      ),
    ]);

    await service.exportCsv(report, _trip());

    expect(shared, hasLength(1));
    expect(p.basename(shared.first.path), 'NotaSpese_Tokyo_2026_2026-07.csv');
    // dart:io's utf8 decoder strips a leading BOM on decode, so the BOM
    // must be checked on the raw bytes rather than the decoded string.
    final bytes = await File(shared.first.path).readAsBytes();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final content = await File(shared.first.path).readAsString();
    expect(content, contains('TOTALE EUR'));

    await dir.delete(recursive: true);
  });
}
