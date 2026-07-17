import 'package:flutter_test/flutter_test.dart';
import 'package:nota_spese/core/constants/categories.dart';
import 'package:nota_spese/data/models/foto.dart';
import 'package:nota_spese/data/models/spesa.dart';
import 'package:nota_spese/data/models/trasferta.dart';

void main() {
  group('Trasferta', () {
    final trasferta = Trasferta(
      id: 1,
      nome: 'Tokyo Q3',
      luogo: 'Tokyo',
      dataInizio: DateTime(2026, 7, 10),
      dataFine: DateTime(2026, 7, 15),
      valutaDefault: 'JPY',
      linguaDefault: 'ja',
      archiviata: false,
      note: 'fiera',
      createdAt: DateTime(2026, 7, 9, 18, 30),
    );

    test('toMap uses DDL column names and ISO dates', () {
      final map = trasferta.toMap();
      expect(map['nome'], 'Tokyo Q3');
      expect(map['data_inizio'], '2026-07-10');
      expect(map['data_fine'], '2026-07-15');
      expect(map['valuta_default'], 'JPY');
      expect(map['lingua_default'], 'ja');
      expect(map['archiviata'], 0);
      expect(map['created_at'], DateTime(2026, 7, 9, 18, 30).toIso8601String());
    });

    test('fromMap(toMap) round-trips', () {
      final back = Trasferta.fromMap(trasferta.toMap());
      expect(back.id, trasferta.id);
      expect(back.nome, trasferta.nome);
      expect(back.dataInizio, trasferta.dataInizio);
      expect(back.dataFine, trasferta.dataFine);
      expect(back.archiviata, trasferta.archiviata);
      expect(back.createdAt, trasferta.createdAt);
    });

    test('handles NULL data_fine (trip in progress) and archiviata=1', () {
      final t = Trasferta.fromMap({
        'id': 2,
        'nome': 'Milano',
        'luogo': null,
        'data_inizio': '2026-07-01',
        'data_fine': null,
        'valuta_default': 'EUR',
        'lingua_default': null,
        'archiviata': 1,
        'note': null,
        'created_at': '2026-07-01T08:00:00.000',
      });
      expect(t.dataFine, isNull);
      expect(t.archiviata, isTrue);
    });
  });

  group('Spesa', () {
    final spesa = Spesa(
      id: 5,
      trasfertaId: 1,
      data: DateTime(2026, 7, 11),
      categoria: Categoria.cena,
      fornitore: 'Ichiran',
      importo: 3200,
      valuta: 'JPY',
      importoEur: 19.5,
      tassoCambio: 0.0061,
      note: null,
      ocrEngine: 'mlkit',
      createdAt: DateTime(2026, 7, 11, 21, 5),
    );

    test('toMap stores categoria.name and DDL column names', () {
      final map = spesa.toMap();
      expect(map['trasferta_id'], 1);
      expect(map['data'], '2026-07-11');
      expect(map['categoria'], 'cena');
      expect(map['importo'], 3200);
      expect(map['valuta'], 'JPY');
      expect(map['importo_eur'], 19.5);
      expect(map['ocr_engine'], 'mlkit');
    });

    test('fromMap(toMap) round-trips including enum', () {
      final back = Spesa.fromMap(spesa.toMap());
      expect(back.categoria, Categoria.cena);
      expect(back.importo, 3200);
      expect(back.importoEur, 19.5);
      expect(back.data, DateTime(2026, 7, 11));
    });

    test('manual entry: importo_eur, tasso_cambio, ocr_engine all null', () {
      final s = Spesa.fromMap({
        'id': 6,
        'trasferta_id': 1,
        'data': '2026-07-12',
        'categoria': 'taxi',
        'fornitore': null,
        'importo': 12.0,
        'valuta': 'EUR',
        'importo_eur': null,
        'tasso_cambio': null,
        'note': null,
        'ocr_engine': null,
        'created_at': '2026-07-12T10:00:00.000',
      });
      expect(s.importoEur, isNull);
      expect(s.ocrEngine, isNull);
      expect(s.categoria, Categoria.taxi);
    });
  });

  group('Foto', () {
    test('round-trips with relative paths', () {
      final foto = Foto(
        id: 3,
        spesaId: 5,
        filePath: 'receipts/5.jpg',
        thumbPath: 'thumbnails/5.jpg',
        createdAt: DateTime(2026, 7, 11, 21, 6),
      );
      final back = Foto.fromMap(foto.toMap());
      expect(back.spesaId, 5);
      expect(back.filePath, 'receipts/5.jpg');
      expect(back.thumbPath, 'thumbnails/5.jpg');
      expect(back.createdAt, foto.createdAt);
    });
  });
}
