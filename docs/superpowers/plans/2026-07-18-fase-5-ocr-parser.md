# Fase 5 — OCR + parser multilingua Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Riconoscimento scontrino end-to-end: foto → OCR (ML Kit default / Claude opzionale) → parser multilingua IT/EN/JA/SR/DE → form spesa pre-compilato. IA locale rimandata (gate benchmark bloccato — vedi spec).

**Architecture:** Due livelli in `lib/services/ocr/`: `OcrService` (interfaccia image→testo, impl. `MlkitOcrService`) e `RecognitionOrchestrator` (sceglie motore, fallback Claude→ML Kit, applica il parser). Parser = estrattori puri + `LanguageProfile` dati-puri per lingua. `ClaudeOcrService` = raw HTTP `/v1/messages` con structured outputs (salta il parser). UI: selettore motore nel bottom sheet FAB, progress fullscreen, `SpesaFormScreen` pre-compilato con banner, campo API key minimale in Impostazioni.

**Tech Stack:** `google_mlkit_text_recognition`, `flutter_secure_storage`, `http` (+ `http/testing.dart` MockClient nei test).

**Spec:** `docs/superpowers/specs/2026-07-18-fase-5-ocr-parser-design.md` (approvata 2026-07-18).

## Global Constraints

- UI in italiano; codice/commit/identificatori in inglese. Mai filesystem/HTTP dai controller UI: solo service.
- **Mai bloccare il flusso**: qualunque fallimento OCR/parser → form apribile (vuoto), mai crash, mai dialog bloccante d'errore.
- API key mai in log, commit, SharedPreferences o messaggi d'errore.
- Widget test col DB: `databaseFactoryFfiNoIsolate`; IO reale mai nel body di `testWidgets` (gotcha fase 4 — preparare file in `setUp`, `tester.runAsync` per IO da tap); scroll: `scrollUntilVisible` + `ensureVisible` con Scrollable esplicito della ListView.
- Motori v1.0: `OcrEngine.mlkit` e `OcrEngine.claude`; `'local_ai'` NON va aggiunto all'enum (rimandato, il DB lo prevede solo come stringa).
- Claude API: modello **`claude-haiku-4-5`** (deciso fase 0, non cambiare), endpoint `https://api.anthropic.com/v1/messages`, header `x-api-key` + `anthropic-version: 2023-06-01`, structured outputs via `output_config.format` (type `json_schema`, `additionalProperties: false`).
- Verifica fase: `flutter analyze` zero issue + `flutter test` verde (102 esistenti + nuovi); device/emulatore = SKIP esplicito (gotcha ambiente).
- Bump a fine fase: `pubspec.yaml` `0.6.0+6` + `lib/version.dart` `'0.6.0'`.

## File Structure

- Modify: `pubspec.yaml` (deps)
- Create: `lib/services/ocr/parsed_receipt.dart` (`OcrEngine`, `ParsedReceipt`)
- Create: `lib/services/ocr/ocr_service.dart` (interfaccia)
- Create: `lib/services/ocr/language_profiles.dart` (dati puri per lingua)
- Create: `lib/services/ocr/receipt_parser.dart` (estrattori + parse + inferenza valuta)
- Create: `lib/services/ocr/mlkit_ocr_service.dart` (wrapper nativo, no test host)
- Create: `lib/services/ocr/claude_ocr_service.dart`
- Create: `lib/services/ocr/recognition_orchestrator.dart`
- Create: `lib/services/settings/api_key_store.dart` (thin wrapper flutter_secure_storage)
- Create: `lib/ui/spese/ocr_progress.dart` (progress fullscreen)
- Modify: `lib/services/settings/settings_service.dart` (+`ocrEngineDefault`)
- Modify: `lib/ui/spese/spesa_form_screen.dart` (parsed + banner + riprova)
- Modify: `lib/ui/trasferte/trasferta_detail_screen.dart` (sheet motore + flusso OCR)
- Modify: `lib/ui/shell/home_shell.dart` (voce API key in Impostazioni), `lib/app.dart`, `lib/main.dart`, `lib/ui/trasferte/trasferte_list_screen.dart` (plumbing)
- Test: `test/language_profiles_test.dart`, `test/receipt_parser_test.dart`, `test/receipt_fixtures_test.dart`, `test/claude_ocr_service_test.dart`, `test/recognition_orchestrator_test.dart`; Modify: `test/settings_service_test.dart`, `test/spesa_form_screen_test.dart`, `test/trasferta_detail_screen_test.dart`, `test/home_shell_test.dart`
- Fixtures: `test/fixtures/receipts/<it|en|ja|sr|de>/<nome>.txt` + `<nome>.expected.json`

---

### Task 1: Dipendenze

**Files:** Modify `pubspec.yaml`

- [ ] **Step 1:** `flutter pub add google_mlkit_text_recognition flutter_secure_storage http`
- [ ] **Step 2:** `flutter analyze` zero issue; `flutter test` → 102 test ancora verdi. Nessuna modifica manifest (ML Kit TR non richiede permessi; compileSdk 36 già ok).

### Task 2: Modello risultato, interfaccia OCR, profili lingua (TDD)

**Files:** Create `parsed_receipt.dart`, `ocr_service.dart`, `language_profiles.dart`; Test `test/language_profiles_test.dart`

**Produces:**

```dart
// parsed_receipt.dart
enum OcrEngine { mlkit, claude } // .name = valore colonna spese.ocr_engine

class ParsedReceipt {
  const ParsedReceipt({this.importo, this.valuta, this.data, this.fornitore,
      this.lingua, required this.engine, this.rawText = ''});
  final double? importo;
  final String? valuta;    // ISO 4217; null → il form usa valuta_default trasferta
  final DateTime? data;    // null → il form mette oggi
  final String? fornitore;
  final String? lingua;    // 'it'|'en'|'ja'|'sr'|'de'
  final OcrEngine engine;
  final String rawText;
  bool get isEmpty => importo == null && data == null && fornitore == null;
}

// ocr_service.dart
abstract class OcrService {
  Future<String> recognizeText(String imagePath); // testo grezzo, righe separate da \n
}

// language_profiles.dart
enum AmountNumberFormat { commaDecimal /*1.234,56*/, dotDecimal /*1,234.56*/, integerOnly /*1,234 JPY*/ }
class ReceiptDatePattern { const ReceiptDatePattern(this.regex, this.order); final RegExp regex; final String order; /* 'dmy'|'mdy'|'ymd' */ }
class LanguageProfile {
  final String code;
  final List<String> totalKeywords;     // lowercase, per priorità
  final List<String> negativeKeywords;  // lowercase
  final List<ReceiptDatePattern> datePatterns;
  final AmountNumberFormat numberFormat;
  final String? defaultCurrency;        // ja→JPY, sr→RSD, de→EUR, it→EUR, en→null
}
const Map<String, LanguageProfile> languageProfiles = {...}; // it, en, ja, sr, de
```

Contenuto profili (dalla spec): keyword totale `totale/tot.` · `total/amount due/balance due` · `合計/総計/お会計` · `ukupno/укупно/za uplatu` · `summe/gesamt/gesamtbetrag/zu zahlen`; negative `subtotale/resto/contante/iva/sconto` · `subtotal/change/tax/cash/discount` · `小計/お預り/お釣/釣銭/税` · `međuzbir/povraćaj/pdv/повраћај` · `zwischensumme/mwst/rückgeld/bar`; date `dd/MM/yyyy` e `dd-MM-yyyy` (it/en/sr), `MM/dd/yyyy` (solo en, dopo dmy), `yyyy年M月d日` + `yyyy/MM/dd` (ja), `dd.MM.yyyy` (de/sr). Rilevazione script in `language_profiles.dart`: `String? detectScript(String text)` → `'ja'` se contiene CJK (`぀-ヿ一-鿿`), `'sr'` se cirillico (`Ѐ-ӿ`), altrimenti null.

- [ ] **Step 1:** test: 5 profili presenti, ogni profilo ha keyword+date+format non vuoti; `detectScript` su stringhe JA/cirillico/latino.
- [ ] **Step 2:** run → rosso; implementa; run → verde; `flutter analyze` pulito.

### Task 3: Estrattore importo (TDD)

**Files:** Create `receipt_parser.dart` (prima parte); Test `test/receipt_parser_test.dart`

**Produces (funzioni top-level o statiche in `receipt_parser.dart`):**

```dart
double? parseAmountToken(String token, AmountNumberFormat format); // '1.234,56'→1234.56 ecc.; null se non numero
double? extractAmount(String text, LanguageProfile profile);
```

Regole: righe con keyword totale (case-insensitive) e senza keyword negativa → prendi il numero più a destra della riga (o della riga successiva se la riga keyword non ha numeri — layout a colonne OCR); più righe keyword → priorità ordine keyword, poi valore maggiore. Nessuna keyword → valore massimo plausibile su tutto il testo (esclse righe negative; plausibile = > 0, ≤ 1.000.000). Numeri con simbolo valuta attaccato (`€12,50`, `¥1,200`) accettati.

- [ ] **Step 1:** test rossi: formati numero per i 3 `AmountNumberFormat`; keyword IT/EN/JA/SR/DE; riga negativa scartata (subtotal < total); fallback massimo; numero su riga successiva alla keyword.
- [ ] **Step 2:** implementa minimo; verde; analyze pulito.

### Task 4: Estrattori data e fornitore (TDD)

**Files:** Modify `receipt_parser.dart`; Test `test/receipt_parser_test.dart`

**Produces:**

```dart
DateTime? extractDate(String text, LanguageProfile profile, {DateTime? now}); // now iniettabile nei test
String? extractVendor(String text);
```

Data: prima regex del profilo che matcha con data plausibile (≤ now, ≥ now − 730 giorni); implausibile → continua a cercare; niente → null. Fornitore: prime 3 righe non vuote, scarta righe che matchano indirizzo/P.IVA/telefono/URL (regex comuni: `\d{5}`, `p\.?\s?iva`, `tel`, `www\.|http`, righe quasi solo cifre/punteggiatura); prima riga superstite, trim, null se nessuna.

- [ ] **Step 1:** test rossi: date nei 4 formati (incl. `2026年7月18日`), data futura scartata, data 3 anni fa scartata, nessuna data → null; fornitore prima riga pulita, P.IVA/telefono scartati, testo vuoto → null.
- [ ] **Step 2:** implementa; verde; analyze pulito.

### Task 5: parse() — selezione lingua, score, inferenza valuta (TDD)

**Files:** Modify `receipt_parser.dart`; Test `test/receipt_parser_test.dart`

**Produces:**

```dart
String? inferCurrencyFromText(String text); // simboli/codici espliciti: €→EUR, £→GBP, $→USD, CHF, дин./din/RSD→RSD, ¥/円→JPY
class ReceiptParser {
  ParsedReceipt parse(String text, {String? linguaHint});
  // engine NON è del parser: l'orchestratore fa copyWith/costruisce ParsedReceipt col motore giusto
}
```

Flusso `parse`: 1) `detectScript` → se ja/sr forza quel profilo come primo candidato; 2) altrimenti `linguaHint` primo, poi gli altri; 3) per ogni candidato calcola estrazione + score (2 punti importo via keyword, 1 importo via fallback, 1 data, 1 fornitore, +1 keyword totale presente) → vince score max, a pari merito il primo provato; 4) valuta = `inferCurrencyFromText` ?? `profilo.defaultCurrency` (null per EN senza simboli → il form userà la trasferta); 5) `lingua` = profilo vincente; qualunque eccezione interna → try/catch → `ParsedReceipt` vuoto con rawText. `ParsedReceipt` costruito con `engine: OcrEngine.mlkit` di default e un metodo `copyWith({OcrEngine? engine})`.

- [ ] **Step 1:** test rossi: hint rispettato; testo JA senza hint → profilo ja; hint sbagliato ma score migliore altrove → override; cascata valuta (simbolo vince su lingua, EN senza simbolo → null); testo spazzatura → `isEmpty` true, no throw.
- [ ] **Step 2:** implementa; verde; analyze pulito.

### Task 6: Suite fixture

**Files:** Create `test/fixtures/receipts/**`, `test/receipt_fixtures_test.dart`

Per lingua 3-4 fixture sintetiche realistiche (supermercato, ristorante, taxi/hotel) + casi limite globali (`edge/` dir: senza keyword totale, senza data, multivaluta nel testo). Ogni `<nome>.txt` affiancato da `<nome>.expected.json`:

```json
{ "importo": 42.50, "valuta": "EUR", "data": "2026-07-15", "fornitore": "Trattoria da Mario", "lingua": "it" }
```

Campi null ammessi. Il test scandisce `test/fixtures/receipts/` ricorsivamente: per ogni coppia txt/json esegue `parser.parse(text, linguaHint: <dir lingua, null per edge/>)` e confronta i 5 campi (importo con tolleranza 0.001). Aggiungere uno scontrino reale dopo = zero codice.

- [ ] **Step 1:** scrivi 2 fixture IT + test harness → verde.
- [ ] **Step 2:** completa le fixture (≥3 per lingua + ≥3 edge); itera sul parser finché tutte verdi (i fix al parser restano in `receipt_parser.dart`, con test unit aggiunti se emerge un caso generale).
- [ ] **Step 3:** `flutter test` completo verde.

### Task 7: SettingsService.ocrEngineDefault + ApiKeyStore

**Files:** Modify `settings_service.dart`; Create `api_key_store.dart`; Test modify `test/settings_service_test.dart`

**Produces:**

```dart
// settings_service.dart (import parsed_receipt.dart per OcrEngine)
Future<OcrEngine> get ocrEngineDefault; // SharedPreferences 'ocr_engine', default mlkit; valore ignoto → mlkit
Future<void> setOcrEngineDefault(OcrEngine engine);

// api_key_store.dart — thin wrapper, niente logica → niente test host (pattern MlkitOcrService)
class ApiKeyStore {
  ApiKeyStore([FlutterSecureStorage? storage]); // default const FlutterSecureStorage()
  static const _key = 'claude_api_key';
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}
```

I consumer (orchestratore, UI) ricevono `Future<String?> Function()` — testabili con lambda fake.

- [ ] **Step 1:** test rossi su ocrEngineDefault (default, set→get, valore corrotto → mlkit) con `SharedPreferences.setMockInitialValues`.
- [ ] **Step 2:** implementa entrambi; verde; analyze pulito.

### Task 8: ClaudeOcrService (TDD, MockClient)

**Files:** Create `claude_ocr_service.dart`; Test `test/claude_ocr_service_test.dart`

**Produces:**

```dart
class ClaudeOcrException implements Exception { final String message; }

class ClaudeOcrService {
  ClaudeOcrService({required Future<String?> Function() apiKeyProvider, http.Client? client, Duration timeout = const Duration(seconds: 30)});
  Future<ParsedReceipt> extract(String imagePath, {String? linguaHint});
}
```

Richiesta: `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`. Body: `model: 'claude-haiku-4-5'`, `max_tokens: 1024`, `messages` = un turno user con blocco `image` (`source: {type: base64, media_type: image/jpeg, data: <base64 file>}`) + blocco `text` (prompt: estrai i campi dallo scontrino; hint lingua se presente), e:

```json
"output_config": {"format": {"type": "json_schema", "schema": {
  "type": "object",
  "properties": {
    "importo": {"type": ["number","null"]},
    "valuta": {"type": ["string","null"], "description": "ISO 4217"},
    "data": {"type": ["string","null"], "description": "YYYY-MM-DD"},
    "fornitore": {"type": ["string","null"]},
    "lingua": {"type": ["string","null"], "enum": ["it","en","ja","sr","de",null]}
  },
  "required": ["importo","valuta","data","fornitore","lingua"],
  "additionalProperties": false
}}}
```

Risposta: primo blocco `content` con `type == "text"` → `jsonDecode` → `ParsedReceipt(engine: OcrEngine.claude, rawText: <json text>)`; data parseata con `DateTime.tryParse` (null se invalida). Errori → `ClaudeOcrException`: key null/vuota, status ≠ 200 (mai includere il body con la key nei messaggi), timeout (`TimeoutException`), `SocketException` (offline), JSON non decodificabile. La key non compare MAI in log/eccezioni.

- [ ] **Step 1:** test rossi con `MockClient` (`package:http/testing.dart`) + file immagine finto in temp: successo (verifica headers, model, presenza image base64 e schema nel body; campi mappati); 401 → eccezione; timeout → eccezione; risposta non-JSON → eccezione; key assente → eccezione senza chiamata HTTP.
- [ ] **Step 2:** implementa; verde; analyze pulito.

### Task 9: MlkitOcrService (wrapper nativo, no test host)

**Files:** Create `mlkit_ocr_service.dart`

**Produces:**

```dart
class MlkitOcrService implements OcrService {
  Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text; // righe già \n-separate
    } finally { await recognizer.close(); }
  }
}
```

Commento `[NON-BLOCKING]`: script `latin` — JA richiederebbe `TextRecognitionScript.japanese` (modello aggiuntivo); decisione al primo test su device: se il testo JA esce vuoto, istanziare il recognizer per script in base a hint lingua trasferta. Non verificabile su host (pattern `ReceiptCaptureService`) — verificare al primo build device.

- [ ] **Step 1:** implementa; `flutter analyze` pulito; nessun test host (SKIP esplicito documentato nel commento).

### Task 10: RecognitionOrchestrator (TDD)

**Files:** Create `recognition_orchestrator.dart`; Test `test/recognition_orchestrator_test.dart`

**Produces:**

```dart
class RecognitionResult {
  final ParsedReceipt receipt;
  final bool claudeFallbackToMlkit; // true → UI mostra SnackBar "Claude non raggiungibile, usato ML Kit"
}

class RecognitionOrchestrator {
  RecognitionOrchestrator({required OcrService mlkitOcr, required ClaudeOcrService claudeOcr,
      required ReceiptParser parser, required Future<String?> Function() apiKeyProvider});
  Future<bool> get claudeAvailable; // key presente e non vuota
  Future<RecognitionResult> recognize(String imagePath, {required OcrEngine engine, String? linguaHint});
}
```

Routing: `mlkit` → `mlkitOcr.recognizeText` → `parser.parse(text, linguaHint)` → `copyWith(engine: mlkit)`; `claude` → `claudeOcr.extract`; su `ClaudeOcrException` (o qualunque eccezione Claude) → percorso mlkit con `claudeFallbackToMlkit: true`. Eccezione anche nel percorso mlkit → `ParsedReceipt` vuoto `engine: mlkit`, mai throw verso la UI.

- [ ] **Step 1:** test rossi con `OcrService` fake e `ClaudeOcrService` fake (subclass con override di `extract`): routing mlkit; routing claude ok; claude throws → fallback flag true + risultato mlkit; mlkit throws → receipt vuoto; `claudeAvailable` con provider null/vuoto/valorizzato.
- [ ] **Step 2:** implementa; verde; analyze pulito.

### Task 11: Form conferma — pre-compilazione, banner, riprova (TDD widget)

**Files:** Modify `spesa_form_screen.dart`; Test modify `test/spesa_form_screen_test.dart`

**Produces (nuovi parametri `SpesaFormScreen`, tutti opzionali — chiamate esistenti invariate):**

```dart
final ParsedReceipt? parsed;                       // solo creazione da scatto
final Future<ParsedReceipt?> Function()? onRetryOtherEngine; // null → voce riprova nascosta
```

Comportamento: `parsed != null` → stato iniziale: importo (`AmountInputController.initialText`), valuta (`parsed.valuta ?? valutaDefault`), data (`parsed.data ?? oggi`), fornitore; `ocrEngine` salvato nella Spesa = `initial?.ocrEngine ?? widget.parsed?.engine.name`. Banner sopra l'importo (stile success da design system, `Key('ocr-banner')`): "Compilato dallo scontrino (ML Kit|Claude) · verifica i dati"; se `parsed.isEmpty` → variante warning "Nessun dato riconosciuto — inserisci manualmente". Menu banner (icona ⋮, `Key('ocr-riprova')`, visibile se `onRetryOtherEngine != null`): "Riprova con altro motore" → chiama callback → se risultato non-null sovrascrive SOLO i campi non toccati dall'utente (tracking: confronta valore corrente col valore pre-compilato originale; diverso = toccato → non toccare) e aggiorna banner/engine.

- [ ] **Step 1:** test widget rossi: form con `parsed` → campi pre-compilati + banner col motore; `parsed.isEmpty` → banner warning; salvataggio → `Spesa.ocrEngine == 'mlkit'`; riprova con fake → campo non toccato sovrascritto, campo modificato dall'utente preservato; form senza `parsed` → nessun banner (regressione).
- [ ] **Step 2:** implementa; verde; test esistenti del form ancora verdi; analyze pulito.

### Task 12: Flusso scatta→OCR→form + selettore motore + progress (widget test e2e)

**Files:** Create `ocr_progress.dart`; Modify `trasferta_detail_screen.dart`, `trasferte_list_screen.dart`, `home_shell.dart`, `app.dart`, `main.dart`; Test modify `test/trasferta_detail_screen_test.dart`

**Produces:**

- `ocr_progress.dart`: `Future<RecognitionResult?> showOcrProgress(BuildContext context, Future<RecognitionResult> future)` — dialog fullscreen scuro (`AppColors.surfaceDark`, `CircularProgressIndicator`, testo "Riconoscimento in corso…", pulsante Annulla `Key('ocr-annulla')`). Annulla → pop con null (il future viene ignorato); completamento → pop col risultato.
- `TrasfertaDetailScreen`: nuovo parametro `RecognitionOrchestrator orchestrator` + `SettingsService settingsService`. Bottom sheet FAB: sotto "Scatta scontrino" riga `Key('sheet-motore')` "Motore: ML Kit ▾" (valore iniziale = `settingsService.ocrEngineDefault`; tap → scelta ML Kit/Claude per questo scatto; Claude `enabled` solo se `orchestrator.claudeAvailable`). Flusso scatta: capture (fase 4, invariato) → `showOcrProgress(context, orchestrator.recognize(path, engine: scelto, linguaHint: trasferta.linguaDefault))` → null (annullo) → ritorno al dettaglio, foto scartata; risultato → `_openSpesaForm(pendingFoto: path, parsed: result.receipt, ...)` con `onRetryOtherEngine` = lambda che ri-esegue `recognize` sulla stessa foto con l'altro motore; `claudeFallbackToMlkit` → SnackBar "Claude non raggiungibile, usato ML Kit". Caso cirillico (spec): `parsed.isEmpty && trasferta.linguaDefault == 'sr'` → SnackBar suggerisce Claude (se disponibile) o messaggio che serve la API key.
- Plumbing: `main.dart` costruisce `ApiKeyStore`, `ClaudeOcrService`, `MlkitOcrService`, `ReceiptParser`, `RecognitionOrchestrator` e li passa lungo `app.dart` → `home_shell.dart` → `trasferte_list_screen.dart` → detail (pattern fase 4).

- [ ] **Step 1:** test widget rossi con orchestratore fake iniettato: sheet mostra riga motore; scatta (capture fake) → progress → form aperto con banner e campi pre-compilati; annulla progress → nessun form; fallback flag → SnackBar. (Gotcha: fake senza IO reale → niente runAsync necessario oltre al pattern fase 4 esistente.)
- [ ] **Step 2:** implementa + aggiorna costruttori nei test esistenti; tutto verde; analyze pulito.

### Task 13: Impostazioni — API key minimale (TDD widget)

**Files:** Modify `home_shell.dart`; Test modify `test/home_shell_test.dart`

**Produces:** `_ImpostazioniPlaceholder` → `ImpostazioniMinimal` (stesso file): mantiene testo "in arrivo (fase 8)" + versione, aggiunge Card "Claude API key" con `TextField` mascherato (`obscureText: true`, `Key('campo-api-key')`), stato attuale ("Configurata" / "Non configurata" — mai mostrare la key), pulsanti Salva (`Key('salva-api-key')`) e Rimuovi (`Key('rimuovi-api-key')`, visibile solo se configurata). Legge/scrive via `ApiKeyStore` iniettato in `HomeShell` (nuovo parametro; nei test un fake in-memory che estende `ApiKeyStore` overridando read/write/delete). Salvataggio → SnackBar conferma, campo svuotato. Sotto, Card "Motore OCR predefinito": `SegmentedButton<OcrEngine>` (`Key('motore-default')`) su `SettingsService.ocrEngineDefault`; opzione Claude disabilitata se key non configurata (e se il default era claude e la key viene rimossa → torna mlkit).

- [ ] **Step 1:** test widget rossi con fake store: stato iniziale non configurata; salva → write chiamato + stato configurata; rimuovi → delete; key mai renderizzata in chiaro; selettore motore persiste il default e disabilita Claude senza key.
- [ ] **Step 2:** implementa; verde; analyze pulito.

### Task 14: Chiusura fase

- [ ] Bump `pubspec.yaml` → `0.6.0+6`, `lib/version.dart` → `'0.6.0'`.
- [ ] `flutter analyze` zero issue + `flutter test` tutto verde (conteggio finale nel report).
- [ ] `ToDo.md` fase 5: spunte con note; SKIP espliciti: `MlkitOcrService` su device, scontrino reale, gate benchmark IA locale + `LocalAiOcrService` + prompt few-shot + Gemini Nano (rimandati, decisione 2026-07-18 in spec); nota script latin ML Kit da verificare su device.
- [ ] `Specifiche.md`: tabella package (+3 deps: `google_mlkit_text_recognition`, `flutter_secure_storage`, `http`), nota "IA locale rimandata a gate benchmark su device (2026-07-18)" nella sezione OCR, selettore motore default documentato in §Impostazioni.
- [ ] Memoria persistente aggiornata (stato fase 5, gotcha nuovi emersi).
- [ ] Commit NON automatico: proporre all'utente (regola globale).
