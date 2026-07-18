# Fase 5 — OCR + parser multilingua — Design

Data: 2026-07-18 · Stato: approvato (brainstorming) · Fonte requisiti: `ToDo.md` fase 5, `Specifiche.md` §OCR, `docs/catena-detection-ocr.md`

## Scope

**Dentro:** interfaccia `OcrService`, `MlkitOcrService`, `receipt_parser` (IT/EN/JA/SR/DE) con suite fixture, `ClaudeOcrService` (structured outputs), orchestratore con fallback, inferenza valuta, selettore motore (globale + per scatto), progress fullscreen, form conferma pre-compilato, campo API key minimale.

**Fuori (rimandato, decisione 2026-07-18):** gate benchmark IA locale, `LocalAiOcrService`, prompt few-shot, Gemini Nano — tutti richiedono device reale (ambiente bloccato, vedi gotcha in `CLAUDE.md`). Il selettore motore è predisposto ma l'opzione "IA locale" resta nascosta. `image_cropper` resta rimandato (fase 4).

## Architettura e flusso

```
FAB → bottom sheet:
  "📷 Scatta scontrino" (si abilita in questa fase)
  + riga selettore motore (default globale, override per scatto)
     ↓
ReceiptCaptureService (fase 4, esistente) → foto compressa
     ↓
Progress fullscreen (annullabile)
     ↓
RecognitionOrchestrator (nuovo):
  motore = mlkit  → MlkitOcrService (image→testo) → ReceiptParser (testo→campi)
  motore = claude → ClaudeOcrService (image→campi JSON, salta parser)
                    offline/errore → fallback automatico ML Kit + avviso
     ↓
ParsedReceipt { importo?, valuta?, data?, fornitore?, linguaRilevata?, engine, rawText }
     ↓
SpesaFormScreen pre-compilato + banner "Compilato dallo scontrino · verifica i dati"
→ salvataggio con ocr_engine valorizzato ('mlkit' | 'claude')
```

Due livelli distinti:
- `OcrService` (interfaccia): solo immagine → testo grezzo. Implementazione: `MlkitOcrService`.
- `RecognitionOrchestrator`: sceglie il motore, gestisce fallback e decide se serve il parser. La UI vede solo l'orchestratore; i chiamanti non conoscono il motore.

File in `lib/services/ocr/` (struttura da `Specifiche.md`):

| File | Responsabilità |
|---|---|
| `ocr_service.dart` | interfaccia astratta image→testo |
| `mlkit_ocr_service.dart` | wrapper `google_mlkit_text_recognition` (unico non testabile su host) |
| `claude_ocr_service.dart` | Vision API `claude-haiku-4-5` + structured outputs, `http.Client` iniettabile |
| `receipt_parser.dart` | estrattori + selezione profilo lingua |
| `language_profiles.dart` | dati puri per lingua (keyword, regex, formati) |
| `parsed_receipt.dart` | modello risultato |
| `recognition_orchestrator.dart` | routing motore, fallback, error handling |

## Parser (approccio A: estrattori + profili lingua)

Scelto tra: (A) estrattori comuni + profili lingua dati-puri; (B) classe parser per lingua; (C) parser generico unico. B scartato per duplicazione, C per falsi positivi cross-lingua (separatori decimali e formati data incompatibili tra lingue).

`LanguageProfile` per IT/EN/JA/SR/DE + pattern comuni:
- **keyword totale** (per priorità): `totale/tot.` · `total/amount due` · `合計/総計/お会計` · `ukupno/укупно` · `summe/gesamt/gesamtbetrag`
- **keyword negative** (escludono la riga): `subtotale/resto/contante/iva`, `subtotal/change/tax`, `小計/お預り/釣`, `mwst/rückgeld`, `međuzbir/povraćaj`
- **regex data**: `dd/MM/yyyy` (IT/EN-UK/SR), `MM/dd/yyyy` (solo EN-US), `yyyy年M月d日` + `yyyy/MM/dd` (JA), `dd.MM.yyyy` (DE/SR)
- **formato numeri**: `1.234,56` (IT/DE/SR) · `1,234.56` (EN) · `1,234` senza decimali (JPY)
- **simboli/codici valuta** riconoscibili nel testo

Tre estrattori, funzioni pure `(testo, profilo) → valore`:
1. **Importo**: righe con keyword totale → numero più a destra/maggiore su quelle righe; righe con keyword negativa scartate; nessuna keyword → valore massimo plausibile nel testo (fallback da ToDo).
2. **Data**: prima regex con data plausibile (≤ oggi, ≥ oggi − 2 anni); nessuna → `null` (il form mette oggi — mai bloccare).
3. **Fornitore**: prime 1-3 righe non vuote, scartando righe indirizzo/P.IVA/telefono (regex comuni); nessuna → `null`.

**Selezione lingua:** hint = `lingua_default` trasferta → quel profilo per primo; se l'importo non esce, prova gli altri profili e vince lo score migliore (n. campi estratti + keyword match). Rilevazione script: caratteri CJK → JA, cirillico → SR.

## Inferenza valuta

Cascata:
1. simbolo/codice esplicito nel testo (`€`, `£`, `$`, `CHF`, `дин`/`RSD`, `¥`/`円`) → vince
2. tabella lingua→valuta: JA→JPY, SR→RSD, DE→EUR, IT→EUR; EN ambigua → nessuna inferenza
3. `valuta_default` trasferta
4. correzione utente nel form (currency_picker esistente)

## UI

- **Bottom sheet FAB**: "📷 Scatta scontrino" abilitato; riga compatta "Motore: ML Kit ▾" → scelta per il singolo scatto; Claude visibile solo con API key salvata, disabilitato offline.
- **Progress fullscreen** scuro (`surfaceDark`) durante il riconoscimento, annullabile.
- **Form conferma** = `SpesaFormScreen` esistente + parametro `ParsedReceipt`: campi pre-compilati, banner success "Compilato dallo scontrino (<motore>) · verifica i dati", foto già agganciata (flusso fase 4), `ocr_engine` salvato.
- **"Riprova con altro motore"** (menu del banner): ri-esegue il riconoscimento sulla stessa foto con l'altro motore; sovrascrive solo i campi non ancora toccati dall'utente.
- **API key minimale**: voce nella tab Impostazioni → campo mascherato, salva/rimuovi via `flutter_secure_storage`. Schermata completa in fase 8.
- Motore default globale in `SettingsService` (SharedPreferences, default `'mlkit'`).

Dipendenze nuove: `google_mlkit_text_recognition`, `flutter_secure_storage`, `http`.

## Gestione errori

Principio: **mai bloccare il flusso** — al peggio form vuoto compilabile a mano, foto già salvata.

| Caso | Comportamento |
|---|---|
| Testo vuoto/spazzatura (score parser 0) | Form si apre vuoto, banner warning "Nessun dato riconosciuto — inserisci manualmente", `ocr_engine` salvato comunque |
| Cirillico + ML Kit (gap noto) | `lingua_default = sr` + score 0 → banner suggerisce "Prova con Claude" (se key presente), altrimenti messaggio chiaro |
| Claude offline/timeout/errore API | Fallback automatico ML Kit + SnackBar "Claude non raggiungibile, usato ML Kit"; `ocr_engine = 'mlkit'` |
| Claude: risposta fuori schema | Structured outputs lo rende ~impossibile; difesa: parse fallito → trattato come errore API → fallback |
| API key assente | Claude non selezionabile (né default né override) |
| Annullo durante progress | Ritorno al dettaglio, foto temporanea scartata |
| Data implausibile | Scartata → default oggi |
| Eccezione imprevista nel parser | try/catch nell'orchestratore → `ParsedReceipt` vuoto, mai crash |

Sicurezza: API key mai in log/commit; richieste https; immagine base64 nel body.

## Testing

Host-testabile tutto tranne il wrapper ML Kit:

1. **Parser + fixture**: `test/fixtures/receipts/<lingua>/<nome>.txt` — 3-4 sintetiche per lingua (supermercato, ristorante, taxi/hotel) + casi limite (senza keyword totale, senza data, multivaluta). Ogni `.txt` ha accanto `.expected.json` (importo, data, fornitore, valuta); il test scandisce la directory → aggiungere uno scontrino reale dopo = zero codice nuovo. (Fixture sintetiche: decisione 2026-07-18; l'utente potrà aggiungere testi reali.)
2. **Estrattori unit**: formati numero, date per formato, keyword negative, fallback valore massimo.
3. **Inferenza valuta**: cascata simbolo→lingua→trasferta.
4. **ClaudeOcrService**: `http.Client` mockato — successo, timeout, 401, offline → verifica fallback.
5. **Orchestratore**: `OcrService` fake → routing, fallback, score 0.
6. **Widget test form conferma**: pre-compilazione + banner; "riprova con altro motore" con orchestratore fake.
7. **SettingsService**: motore default; secure storage mockato.

Skip espliciti (device non disponibile, pattern fasi precedenti): `MlkitOcrService` reale, scatto→form su scontrino vero, gate benchmark IA locale.

**Criteri di completamento:** `flutter analyze` zero issue · `flutter test` tutto verde (102 esistenti + nuovi) · checkbox `ToDo.md` fase 5 spuntate (con skip espliciti annotati) · bump versione.
