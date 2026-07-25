import '../../data/models/trasferta.dart';

/// Share filename: `NotaSpese_<slug>_<yyyy-MM>.<ext>`. The slug is the trip
/// name with whitespace collapsed to `_` and unsafe characters removed;
/// `yyyy-MM` comes from `dataInizio`.
String exportFileName(Trasferta t, String ext) {
  final slug = t.nome
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
  final safe = slug.isEmpty ? 'trasferta' : slug;
  final ym = '${t.dataInizio.year.toString().padLeft(4, '0')}-'
      '${t.dataInizio.month.toString().padLeft(2, '0')}';
  return 'NotaSpese_${safe}_$ym.$ext';
}
