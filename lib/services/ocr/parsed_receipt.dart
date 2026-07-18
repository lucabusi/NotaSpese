/// OCR engine used to produce a [ParsedReceipt]. `.name` is the value
/// stored in the `spese.ocr_engine` DB column.
enum OcrEngine { mlkit, claude }

/// Fields extracted from a receipt photo, ready to prefill the expense form.
class ParsedReceipt {
  const ParsedReceipt({
    this.importo,
    this.valuta,
    this.data,
    this.fornitore,
    this.lingua,
    required this.engine,
    this.rawText = '',
  });

  final double? importo;
  final String? valuta; // ISO 4217; null → il form usa valuta_default trasferta
  final DateTime? data; // null → il form mette oggi
  final String? fornitore;
  final String? lingua; // 'it'|'en'|'ja'|'sr'|'de'
  final OcrEngine engine;
  final String rawText;

  bool get isEmpty => importo == null && data == null && fornitore == null;

  ParsedReceipt copyWith({OcrEngine? engine}) => ParsedReceipt(
        importo: importo,
        valuta: valuta,
        data: data,
        fornitore: fornitore,
        lingua: lingua,
        engine: engine ?? this.engine,
        rawText: rawText,
      );
}
