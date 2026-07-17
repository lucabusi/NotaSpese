import '../../core/constants/categories.dart';

/// Expense model, mirrors table `spese` (Specifiche.md DDL).
/// `valuta` stays a raw ISO string (not the enum) so unknown codes never
/// crash a read; the Currency enum is the picker's source of truth.
class Spesa {
  const Spesa({
    this.id,
    required this.trasfertaId,
    required this.data,
    required this.categoria,
    this.fornitore,
    required this.importo,
    required this.valuta,
    this.importoEur,
    this.tassoCambio,
    this.note,
    this.ocrEngine,
    required this.createdAt,
  });

  factory Spesa.fromMap(Map<String, Object?> map) => Spesa(
        id: map['id'] as int?,
        trasfertaId: map['trasferta_id'] as int,
        data: DateTime.parse(map['data'] as String),
        categoria: Categoria.values.byName(map['categoria'] as String),
        fornitore: map['fornitore'] as String?,
        importo: (map['importo'] as num).toDouble(),
        valuta: map['valuta'] as String,
        importoEur: (map['importo_eur'] as num?)?.toDouble(),
        tassoCambio: (map['tasso_cambio'] as num?)?.toDouble(),
        note: map['note'] as String?,
        ocrEngine: map['ocr_engine'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final int trasfertaId;
  final DateTime data;
  final Categoria categoria;
  final String? fornitore;
  final double importo; // sempre valuta originale
  final String valuta; // ISO 4217
  final double? importoEur; // NULL se non convertito
  final double? tassoCambio; // NULL se inserito a mano
  final String? note;
  final String? ocrEngine; // 'mlkit'|'local_ai'|'claude'|NULL (manuale)
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'trasferta_id': trasfertaId,
        'data': _isoDate(data),
        'categoria': categoria.name,
        'fornitore': fornitore,
        'importo': importo,
        'valuta': valuta,
        'importo_eur': importoEur,
        'tasso_cambio': tassoCambio,
        'note': note,
        'ocr_engine': ocrEngine,
        'created_at': createdAt.toIso8601String(),
      };
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
