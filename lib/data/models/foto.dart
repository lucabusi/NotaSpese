/// Photo model, mirrors table `foto` (1:1 with spesa via UNIQUE spesa_id).
/// Paths are RELATIVE to the configured photo directory (Specifiche.md §2),
/// so restore/directory changes never break references.
class Foto {
  const Foto({
    this.id,
    required this.spesaId,
    required this.filePath,
    required this.thumbPath,
    required this.createdAt,
  });

  factory Foto.fromMap(Map<String, Object?> map) => Foto(
        id: map['id'] as int?,
        spesaId: map['spesa_id'] as int,
        filePath: map['file_path'] as String,
        thumbPath: map['thumb_path'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  final int? id;
  final int spesaId;
  final String filePath;
  final String thumbPath;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'spesa_id': spesaId,
        'file_path': filePath,
        'thumb_path': thumbPath,
        'created_at': createdAt.toIso8601String(),
      };
}
