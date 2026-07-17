/// Trip model, mirrors table `trasferte` (Specifiche.md DDL).
class Trasferta {
  const Trasferta({
    this.id,
    required this.nome,
    this.luogo,
    required this.dataInizio,
    this.dataFine,
    this.valutaDefault = 'EUR',
    this.linguaDefault,
    this.archiviata = false,
    this.note,
    required this.createdAt,
  });

  factory Trasferta.fromMap(Map<String, Object?> map) => Trasferta(
        id: map['id'] as int?,
        nome: map['nome'] as String,
        luogo: map['luogo'] as String?,
        dataInizio: DateTime.parse(map['data_inizio'] as String),
        dataFine: map['data_fine'] == null
            ? null
            : DateTime.parse(map['data_fine'] as String),
        valutaDefault: map['valuta_default'] as String,
        linguaDefault: map['lingua_default'] as String?,
        archiviata: (map['archiviata'] as int) != 0,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final String nome;
  final String? luogo;
  final DateTime dataInizio;
  final DateTime? dataFine; // NULL = in corso
  final String valutaDefault; // ISO 4217
  final String? linguaDefault; // it|en|ja|sr|de, NULL = auto
  final bool archiviata;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'nome': nome,
        'luogo': luogo,
        'data_inizio': _isoDate(dataInizio),
        'data_fine': dataFine == null ? null : _isoDate(dataFine!),
        'valuta_default': valutaDefault,
        'lingua_default': linguaDefault,
        'archiviata': archiviata ? 1 : 0,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
