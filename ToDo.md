# Nota Spese in Trasferta — ToDo & Setup

> Piano di sviluppo per fasi. Fonte di verità per l'avanzamento: spuntare le checkbox a lavoro **verificato** (criteri in fondo a ogni fase). Specifiche complete: `Specifiche.md`.

## Convenzioni di sviluppo
- Bump di versione (`pubspec.yaml` + `lib/version.dart`) a ogni modifica funzionale.
- Tag nei commenti motivati: `[FIX X]` / `[EXIT-LOG]` / `[NON-BLOCKING]`.
- Codice, commit e identificatori in inglese; UI in italiano.
- Un file = una responsabilità; screen e controller separati (vedi struttura in `Specifiche.md`).
- Mai `sqflite`/filesystem direttamente dai controller: solo repository/service.
- Ogni fase termina con: `flutter analyze` zero issue + test verdi + prova manuale su emulatore/dispositivo.

## 📌 Decisioni prese (2026-07-15)
- **Qualità JPG:** default **70%**, configurabile nelle Impostazioni dell'app (vale solo per le nuove foto).
- **Motore OCR "IA locale":** studio di fattibilità **completato 2026-07-15** (`docs/fattibilita-ia-locale.md`) → **GO condizionato**: ibrido OCR ML Kit + Gemma 3 1B (~529 MB, download on-demand), gate benchmark su dispositivo reale in fase 5; fine-tune 270M in backlog v1.1.
- **Directory foto:** default **storage interno app**, modificabile nelle Impostazioni (v1.0 limitata a directory app-specific — vedi vincolo scoped storage in `Specifiche.md` §2).

---

## Fase 0 — Studio fattibilità IA locale + setup progetto ▢

**0a — Studio di fattibilità OCR "IA locale" (PRIMA di ogni altro task)** ✅ 2026-07-15
- [x] Censire i candidati: VLM on-device (Gemma 3n/4 E2B), ibrido ML Kit + LLM testo (Gemma 3 1B), modelli specifici scontrini (Donut CORD, LayoutLM, fine-tune Gemma 270M), Gemini Nano di sistema
- [x] Criteri di valutazione: dimensione modello, RAM richiesta, latenza per scontrino, multilingua, offline — da fonti pubblicate; la prova su 3-5 scontrini reali è rimandata al **gate benchmark in fase 5** (non eseguibile senza dispositivo)
- [x] Deliverable: `docs/fattibilita-ia-locale.md` — verdetto **GO condizionato**: architettura B (OCR ML Kit → Gemma 3 1B int4 ~529 MB via `flutter_gemma` → JSON), modello scaricato on-demand, VLM 3 GB NO-GO, fine-tune 270M → v1.1
- [x] **Rivalutazione v2** (2026-07-15): esclusi i NO-GO; shortlist modelli locali intercambiabili (Gemma 3 1B primario, Qwen2.5 1.5B per JA/SR, stesso runtime `.task`); SmolVLM 256/500M NO-GO (OCRBench 52-61%, no runtime Flutter); motore Claude fissato: `claude-haiku-4-5` + structured outputs, ~$0,2-0,35/mese a 90 scontrini — GO confermato
- [x] **Valutazione catena detection→OCR** (2026-07-15, `docs/catena-detection-ocr.md`): YOLOv8n (AGPL + training custom) e MobileNetV3-SSDLite (training custom) scartati — detection risolta con **ML Kit Document Scanner** (~0 MB, Play Services, plugin verificato v0.5.0); PaddleOCR scartato come motore principale (~35-40 MB + integrazione nativa senza plugin Flutter) — utile solo per il cirillico → mitigazione via Claude API, eventuale v1.1; **ML Kit Text Recognition v2 confermato**
- [x] Aggiornati `ToDo.md` fase 4/5/8 e `Specifiche.md` in base ai verdetti

**0b — Setup progetto** ✅ 2026-07-16
- [x] `flutter create` (org `it.lucabusi`, pacchetto `nota_spese`) nel repo; target Android; `minSdk 33`, `compileSdk 35`, `ndkVersion "27.0.12077973"` in `android/app/build.gradle.kts`
- [x] `.gitignore` Flutter completo (build/, .dart_tool/, ecc.)
- [x] `analysis_options.yaml` con `flutter_lints`
- [x] Struttura cartelle `lib/` come da `Specifiche.md` (core/, data/, services/, ui/) — placeholder `.gitkeep`
- [x] `lib/version.dart` con costante versione app (0.1.0, allineata a `pubspec.yaml`)
- [x] Tema Material 3 in `core/theme/app_theme.dart`: token colore, Plus Jakarta Sans (`google_fonts`), Material Symbols Rounded — dal Design System in `Specifiche.md`
- [x] Dipendenze fase 0-2 aggiunte con `flutter pub add` (sqflite, path_provider, intl, google_fonts, material_symbols_icons, dev: sqflite_common_ffi)

**Verifica fase 0**
- [x] `docs/fattibilita-ia-locale.md` esiste con verdetto GO/NO-GO motivato
- [x] `flutter analyze` → zero issue (2026-07-16; `flutter test` smoke test verde)
- [ ] App vuota con tema si compila e parte su emulatore — **SKIP esplicito** su questa macchina (SDK Android incompleto + JDK 11, vedi gotcha in `CLAUDE.md`); da verificare appena l'ambiente è completo

## Fase 1 — Data layer ✅ 2026-07-17
- [x] Modelli `Trasferta`, `Spesa`, `Foto` (fromMap/toMap, campi come da DDL in `Specifiche.md`)
- [x] Enum `Categoria` (pranzo·cena·colazione·trasporto·taxi·hotel·parcheggio·carburante·telefono·altro) con icona e label
- [x] Enum valute supportate (EUR, JPY, USD, GBP, CHF, RSD, AED, SGD, …) — nessuna API per la lista; no HRK (kuna → EUR dal 2023)
- [x] `db_helper.dart`: apertura DB, `PRAGMA foreign_keys = ON` a ogni connessione, creazione schema, versione DB
- [x] `TrasfertaRepository`: CRUD + archivia + **delete cascade esplicito in transazione** (file foto → record foto → spese → trasferta)
- [x] `SpesaRepository`: CRUD, spese per trasferta raggruppate per data, totali per categoria e totale trasferta (valuta originale + EUR se disponibile)
- [x] `FotoRepository`: crea/leggi/elimina record + eliminazione file fisici PRIMA del record
- [x] Unit test repository con `sqflite_common_ffi` (CRUD, cascade, totali, FK attive)

**Verifica fase 1**
- [x] `flutter test` verde (39 test, 2026-07-17)
- [x] `flutter analyze` → zero issue (2026-07-17)

## Fase 2 — Shell UI + CRUD trasferte ✅ 2026-07-17
- [x] `home_shell.dart`: `NavigationBar` 3 tab (Trasferte attive / Archivio / Impostazioni)
- [x] Lista trasferte attive: header con totale complessivo €, card trasferta (icona, nome, date, badge valuta, n. spese, totale) — `shared/widgets/trip_card.dart`
- [x] Form crea/modifica trasferta: nome, luogo, date, valuta default, lingua default, note
- [x] Dettaglio trasferta (scheletro): header totale, lista spese vuota, FAB `+`
- [x] Azioni trasferta: archivia / ripristina / elimina (con conferma)
- [x] Tab Archivio: lista `archiviata = 1`, badge ARCHIVIATA
- [x] Controller `ChangeNotifier` per lista/dettaglio, collegati ai repository
- [x] Stati vuoti (nessuna trasferta) con invito all'azione

**Verifica fase 2**
- [ ] Creare/modificare/archiviare/eliminare una trasferta su emulatore senza crash — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensato da widget test del flusso completo (crea/modifica/archivia/elimina, 2026-07-17)
- [x] `flutter analyze` zero issue, test fase 1 ancora verdi (69 test totali, 2026-07-17)

## Fase 3 — Spese (inserimento manuale) ✅ 2026-07-17
- [x] Bottom sheet FAB `+`: "📷 Scatta scontrino" (disabilitato fino a fase 4/5) / "✏️ Inserimento manuale"
- [x] Form spesa: importo originale + valuta, importo EUR opzionale, categoria chip-select, data (default oggi, date picker), fornitore, note — nota: per valuta EUR il campo EUR è nascosto e `importo_eur = importo` (campo manuale solo per valute estere)
- [x] Tastiera numerica custom (griglia 3×4) per importi
- [x] `currency_picker.dart` searchable: filtro testo, valute frequenti in cima (EUR, USD, JPY, GBP, CHF, RSD, AED, SGD)
- [x] Salvataggio/modifica/eliminazione spesa (con conferma)
- [x] Dettaglio trasferta completo: spese raggruppate per data, totali per categoria con barre, totale live
- [x] Unit test: calcolo totali per categoria e formattazione importi

**Verifica fase 3**
- [ ] Flusso completo su emulatore: nuova spesa manuale → appare in lista → totali aggiornati → modifica → elimina — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensato da widget test end-to-end del flusso (crea/modifica/elimina, 2026-07-17)
- [x] `flutter test` + `flutter analyze` verdi (89 test, 2026-07-17)

## Fase 4 — Foto scontrino ✅ 2026-07-17
- [x] Permessi API 33+ (`CAMERA`, `READ_MEDIA_IMAGES`) dichiarati in `AndroidManifest.xml`; richiesta runtime delegata ai plugin (scanner = UI Play Services senza permessi in-app; `image_picker` gestisce CAMERA da sé) — `permission_handler` non necessario in v1.0; rifiuto/annullo → ritorno `null`, flusso interrotto senza crash
- [x] Flusso camera: **ML Kit Document Scanner** come percorso principale (fallback automatico a `image_picker` camera su eccezione); `image_picker` camera/galleria selezionabili dal form ("Aggiungi foto"); pulsante "✎ Edit" / crop in-app implementato in fase 6b
- [x] Punto di aggancio previsto per plugin contrast/brightness (future option v1.1) nel flusso camera (`receipt_capture_service.dart`, commento `[NON-BLOCKING]`)
- [x] `settings_service.dart` **minimale**: qualità JPG (50-90, default 70) + directory foto su `SharedPreferences`
- [x] `photo_service.dart`: compressione JPG (qualità da `SettingsService`, default 70%, max 1920px lato lungo, mai upscale) + thumbnail 300px in `thumbnails/` — originale non conservato; package **`image`** (pure Dart) al posto di `flutter_image_compress` → pipeline unit-testata su host
- [x] Directory foto: default storage interno app (`<documents>/foto`), scelta internal/external in `SettingsService` (UI in fase 8); path salvati **relativi** con separatore `/`
- [x] Form spesa: thumbnail foto se presente (tap → viewer) / area "Aggiungi foto" se assente; aggiunta foto anche a spesa manuale esistente; foto sostituibile/rimovibile
- [x] Viewer foto fullscreen: zoom (`InteractiveViewer`), share (`share_plus`), elimina (con conferma)
- [x] Eliminazione coerente: rimozione spesa → file foto+thumbnail eliminati prima dei record — verificata end-to-end (unit test controller + widget test flusso completo); file lockati/mancanti tollerati (mai bloccare l'eliminazione)

**Verifica fase 4**
- [ ] Su dispositivo/emulatore con camera: scatto → crop → salva → thumbnail in lista → viewer → elimina spesa → file spariti dal filesystem — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensato da widget test e2e con capture fake (scatta→preview→salva→thumb in lista→elimina→file rimossi, 2026-07-17); API Document Scanner (beta) da verificare al primo build su device
- [x] `flutter analyze` + test verdi (102 test, 2026-07-17)

## Fase 5 — OCR + parser multilingua ✅ 2026-07-18
- [x] Interfaccia `OcrService` unica (input immagine → testo grezzo); i chiamanti non conoscono il motore
- [x] `MlkitOcrService` (default, offline) — implementato su `compileSdk 35`+; script latino verificato via unit/widget test — **SKIP esplicito** verifica reale su device (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); limitazione script latino ML Kit da confermare al primo build su dispositivo
- [x] `receipt_parser.dart`: estrazione **importo** (valore maggiore + keyword totale/total/合計/итого/gesamt), **fornitore**, **data** (regex per-lingua, fallback data odierna — mai bloccare il flusso)
- [x] Lingue parser: IT · EN · JA · SR · DE (+ pattern comuni); hint da `lingua_default` trasferta
- [x] Gap cirillico ML Kit (SR): instradamento verso Claude implementato (banner + suggerimento se API key assente)
- [x] Inferenza valuta dalla lingua/paese (JA→JPY, SR→RSD, EN-UK→GBP, CH→CHF, US→USD, area euro→EUR), override da impostazioni trasferta, correzione utente nel form
- [x] Form di conferma pre-compilato con banner "Compilato dallo scontrino · verifica i dati" + indicazione motore usato (`ocr_engine` salvato)
- [x] `ClaudeOcrService` (opzionale): Vision API con modello **`claude-haiku-4-5`** + **structured outputs** (`output_config.format`/`json_schema`), raw HTTP, testato con `MockClient`; disabilitato se API key assente; offline → fallback automatico a ML Kit (`RecognitionOrchestrator`). Campo API key **minimale** in Impostazioni via `flutter_secure_storage` (anticipo — schermata completa in fase 8)
- [ ] **Gate benchmark IA locale comparativo** — **SKIP esplicito, rimandato** (decisione 2026-07-18, vedi `Specifiche.md` §OCR): richiede dispositivo reale non disponibile in questo ambiente; nessuna regressione, motore IA locale resta nascosto finché il gate non è superato
- [ ] `LocalAiOcrService` — **SKIP esplicito, rimandato** (decisione 2026-07-18): subordinato al gate benchmark sopra, non implementato in questa fase
- [ ] Prompt few-shot versionato (`local_ai_prompt.dart`) — **SKIP esplicito, rimandato** (decisione 2026-07-18): subordinato a `LocalAiOcrService`
- [ ] (Opzionale) Gemini Nano via ML Kit Prompt API — **SKIP esplicito, rimandato** (decisione 2026-07-18): bonus non requisito, richiede device per `checkFeatureStatus()`
- [x] Selettore motore: impostazione globale (default ML Kit) in `ImpostazioniMinimal` (`SegmentedButton`) + override per singolo scatto nel bottom sheet FAB e nel form di conferma ("riprova con altro motore"); opzione IA locale non esposta (non implementata)
- [x] Progress OCR fullscreen durante il riconoscimento
- [x] **Suite fixture**: 18 scontrini campione `.txt` per lingua in `test/fixtures/receipts/` + unit test importo/fornitore/data

**Verifica fase 5**
- [x] `flutter test` parser verde su tutte le lingue fixture (227/227 test totali, 2026-07-18)
- [ ] Su dispositivo: scatto scontrino reale → form pre-compilato corretto (almeno IT) — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensato da widget test e2e del flusso capture→progress→form con OCR banner
- [x] Con API key assente: Claude Vision non selezionabile/segnala setup; offline: fallback a ML Kit — verificato con widget test (mock `MockClient`, nessun device richiesto)
- [x] `flutter analyze` → zero issue (2026-07-18)

## Fase 6 — Multi-valuta / conversione EUR ✅ 2026-07-19
- [x] `exchange_service.dart`: conversione via `frankfurter.app` (no key), timeout breve, mai bloccante (tasso storico alla data della spesa; cache in-memory sessione)
- [x] Conversione con badge **AUTO** nel form: conversione **live nel form** con debounce (design 2026-07-19), non al salvataggio
- [x] Offline o preferenza utente: campo EUR editabile manualmente o lasciabile vuoto; pulsante ricalcolo manuale
- [x] Toggle "Tassi di cambio online" in Impostazioni
- [x] Totali trasferta: somma in valuta originale + conversione EUR se disponibile (spese senza EUR escluse dal totale EUR, indicarlo) — già implementati in fase 3 (`countSenzaEur` nell'header), nessuna modifica
- [x] Unit test conversione con http mockato (successo, timeout, offline)
- ~~⚠️ Limite: frankfurter copre solo le ~30 valute ECB: **RSD e AED senza conversione automatica**~~ — **superato il 2026-07-30** (v0.12.0): catena a due fonti in `exchange_service.dart`, tutte le valute dell'enum sono convertibili automaticamente. Vedi fase 7.

**Verifica fase 6**
- [ ] Spesa JPY online → EUR auto compilato; in modalità aereo → campo vuoto editabile, nessun blocco — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensata da unit + widget test con `MockClient`/fake
- [x] `flutter test` (252/252) + `flutter analyze` (zero issue) verdi (2026-07-19)

## Fase 6b — Collaudo su dispositivo reale + bugfix ▢

> Prima fase con l'app in mano all'utente: installazione dell'APK (build GitHub Actions) su dispositivo Android reale, uso in ambiente reale e fix dei bug rilevati. Recupera anche tutte le verifiche **SKIP esplicito** accumulate nelle fasi 0b-6 (ambiente Android incompleto sulla macchina dev).

- [x] Installare l'APK release sul dispositivo reale — **fatto 2026-07-24** (build locale `flutter build apk --release` v0.9.3+14 col fix BUG-04, `adb install -r` su OnePlus CPH2173); la build CI riparte col push di questo fix
- [ ] Collaudo del flusso core: scatta scontrino → scanner/crop → OCR → form pre-compilato → salva → foto in lista → viewer → elimina — **verificato 2026-07-24 fino a "form pre-compilato" (scatta→scanner automatico→OCR→importo/data/fornitore)**; salva→lista→viewer→elimina ancora da ricollaudare su device in una sessione con l'utente
- [ ] Recupero verifiche SKIP delle fasi precedenti:
  - [ ] App parte senza crash, tema corretto (fase 0b)
  - [ ] CRUD trasferte completo senza crash (fase 2)
  - [ ] Spesa manuale: crea → lista → totali → modifica → elimina (fase 3)
  - [ ] Foto: scatto → salva → thumbnail → viewer → eliminazione file dal filesystem; **API Document Scanner verificata funzionante su device (2026-07-24, dopo fix BUG-04)** — scatto→salva→thumbnail→viewer→eliminazione non ancora ricollaudati end-to-end in questa sessione (fase 4)
  - [x] OCR scontrino reale → form pre-compilato corretto: **verificato su device 2026-07-24 (scontrino JP reale: importo, data, fornitore compilati)**; script giapponese ML Kit confermato funzionante in release dopo il fix BUG-04 (fase 5)
  - [ ] Conversione EUR: spesa JPY/USD online → EUR auto; modalità aereo → campo vuoto editabile, nessun blocco (fase 6)
- [ ] Raccolta bug: ogni anomalia rilevata dall'utente registrata qui sotto come checkbox (data, passi per riprodurre, comportamento atteso vs osservato)
- [ ] Fix dei bug raccolti: causa radice (`systematic-debugging`), test di regressione dove la logica è testabile su host, niente fix sintomatici
- [ ] Bump versione a ogni ciclo di fix distribuito; nuova APK via push su main

- [x] Parser JP irrobustito su 14 scontrini giapponesi reali (`scontrini_training/`, non versionati): fullwidth, keyword spaziate, `お買上計`/`計`/`取引金額`, date con spazi e ISO, percentuali, vendor da `加盟店名` — accuratezza field-level 60,7% → 100% (2026-07-20, v0.7.1)
- [x] **OCR geometry-aware + fix glifi ML Kit** (2026-07-22, v0.9.1): harness ML Kit reale on-device misurava field accuracy 62,5% (importo 0/14) perché ML Kit restituisce i blocchi per colonne. Fix: (1) `lib/services/ocr/ocr_layout.dart` — `reconstructReadingOrder` ricostruisce le righe visuali dai bounding box (clustering per overlap verticale ≥50%, sort X in riga), usato da `MlkitOcrService`; (2) `normalizeOcrText` ricongiunge migliaia spezzate (`¥1, 489`); (3) `fixYenGlyphs` (solo script ja) ripara `¥`→`4` sui numeri comma-grouped; (4) keyword ja `クレジット`/`金額` sotto i 合計 espliciti; (5) `_valueNearLine` non ruba più valori da righe negative adiacenti. Risultato su device (OnePlus CPH2173, 3 iterazioni): field accuracy **87,5%** (49/56 — importo 14/14, data 14/14, valuta 14/14, fornitore 7/14), charAcc 35,2% → 73,7%. KO residui solo fornitore per glifi OCR nel nome (`LAWS口N`, `ヨ-ク`).
- [x] **Fornitore geometry/glyph-aware** (2026-07-22, v0.9.2): analisi cause radice dei 7 KO fornitore → 5 fixabili nel parser: (1) riga con `#` = noise (logo garbled `HARD-oF#` sopra la ragione sociale pulita); (2) `_cleanVendor`: trattino ASCII tra katakana → `ー`, `口` CJK tra lettere latine → `O`, lettera latina spuria attaccata a nome katakana rimossa, punteggiatura iniziale rimossa; (3) `_vendorFromLabel` taglia anche a `係員` senza slash. Risultato su device (1 iterazione): fornitore **12/14**, field accuracy **96,4%** (54/56). KO residui non fixabili senza dizionario insegne (= overfit): JP_09 `ユ`→`1`, JP_12 `餃`→`鼓` — errori glifo del motore OCR su singoli caratteri CJK.
- [x] **Fornitore — label `加盟店名` misletta `カ盟店名`** (2026-07-22, v0.9.3, segnalato dall'utente su scontrino taxi reale). Root cause: ML Kit legge 加 (kanji) come カ (katakana) su questa frase fissa dello scontrino card; `_vendorFromLabel` non riconosceva più la label e il parser cadeva sulla prima riga di rumore in cima allo scontrino (`No0 O 1`, numero slip con stessa confusione O/0). Fix: `_vendorLabelPattern` accetta `[加カ]盟店名?`. Test di regressione in `receipt_parser_test.dart`. Diagnosi fatta con `flutter run` collegato al device + print diagnostici temporanei (rimossi dopo la diagnosi): l'OCR/parser funzionavano già, il primo fallimento riportato dall'utente era una build vecchia installata sul device (firma non corrispondente, disinstallata al rebuild).

### Bug rilevati (da compilare durante il collaudo)
- [x] **BUG-01 — Totale trasferta e totale complessivo sempre 0,00** (2026-07-21, APK release GitHub Actions). Causa radice: `android/app/src/main/AndroidManifest.xml` non dichiarava `android.permission.INTERNET` (i manifest debug/profile la aggiungono da template Flutter, quindi il difetto si vedeva solo in release). Ogni chiamata a frankfurter.app falliva con SocketException → `ExchangeService.convert()` null → campo EUR vuoto → `importo_eur` NULL → `SUM(importo_eur)` = 0. Fix: permesso dichiarato nel manifest main + test di regressione `test/android_manifest_test.dart`. v0.8.0
- [x] **BUG-02 — ML Kit non estrae nulla dagli scontrini giapponesi** (2026-07-21). Causa radice: `MlkitOcrService` usava sempre `TextRecognitionScript.latin` (decision point annotato in fase 4), che sul giapponese restituisce testo vuoto; inoltre il modello japanese è `compileOnly` nel plugin, quindi non presente nell'APK. Fix: `MlkitOcrService.scriptFor(linguaHint)` sceglie il riconoscitore dalla lingua della trasferta, `linguaHint` propagato da `RecognitionOrchestrator` a `OcrService.recognizeText`, dipendenza `com.google.mlkit:text-recognition-japanese` aggiunta in `build.gradle.kts` e relativo `-dontwarn` rimosso. v0.8.0
- [x] **Nota post-fix BUG-01:** le spese già salvate restavano con `importo_eur` NULL e andavano riaperte una a una. **Risolto il 2026-07-30** (v0.12.0): il pulsante "Ricalcola" nell'header del dettaglio trasferta converte in blocco tutte le spese senza `importo_eur`.
- [x] **BUG-03 — Importo primario in EUR invece che nella valuta originale** (2026-07-21). L'app dava rilievo a un dato derivato e opzionale (`importo_eur`): senza conversione tutte le schermate mostravano `€ 0,00` pur avendo spese registrate. Fix: totali primari per valuta originale in header dettaglio e card lista, EUR come riga secondaria nascosta quando manca o quando è già l'unica valuta, categorie in valuta originale se la trasferta ne ha una sola, nota `esclude N spese senza conversione` sul totale complessivo. Spec `docs/superpowers/specs/2026-07-21-importo-primario-valuta-originale-design.md`. v0.8.0
- [x] **Ritaglio dopo lo scatto** (2026-07-21, v0.9.0): schermata di crop in-app tra cattura e OCR (`lib/ui/foto/crop_screen.dart` + `lib/services/photo/crop_service.dart`, Dart puro sopra il pacchetto `image`, nessuna dipendenza nativa). Il rettangolo parte sull'immagine intera: confermare senza trascinare non ricodifica il file. Il ritaglio vale sia per il testo passato all'OCR sia per la foto salvata. Spec: `docs/superpowers/specs/2026-07-21-crop-scontrino-design.md`.
- [x] **BUG-04 — scanner automatico e OCR non funzionano nell'APK release** (2026-07-24, segnalato dall'utente: "in debug funziona, nell'APK no"). Causa radice **provata su device** con `adb logcat`: sia `google_mlkit_document_scanner` sia `google_mlkit_text_recognizer` lanciavano `NullPointerException` nella stessa classe interna ML Kit offuscata (`mlkit_common.zzsr`, de-offuscata dal `mapping.txt`), perché **R8 full mode** (default AGP 8+) ottimizza troppo aggressivamente le classi interne su cui i plugin Flutter fanno affidamento. I due `catch (_)` in `_captureScatta`/orchestrator mascheravano le eccezioni → lo scanner ripiegava sulla fotocamera semplice (niente auto-crop) e l'OCR restituiva vuoto. In debug non c'è minificazione, quindi tutto funzionava: **stesso codice, differenza solo di build mode**. Fix: `android.enableR8.fullMode=false` in `android/gradle.properties` (commit `da473bc`). **Verificato su device** (OnePlus CPH2173, rebuild `flutter build apk --release` + `adb install -r`): 0 errori MethodChannel, scanner automatico con rilevamento bordi funzionante, OCR compila importo/data/fornitore. Gotcha registrato: l'harness OCR integration gira in debug/profile, quindi non validava mai la release → il bug è rimasto invisibile fino al collaudo manuale.

**Verifica fase 6b**
- [ ] Flusso core completo eseguito su dispositivo reale senza crash né bug bloccanti
- [ ] Tutti i bug raccolti fixati o esplicitamente rimandati (con motivazione) a v1.1
- [ ] `flutter test` + `flutter analyze` verdi dopo i fix

## Fase 6c — Training e affinamento parser su scontrini reali (JP) ✅ 2026-08-20

> Dataset: **53 foto** di scontrini giapponesi in `scontrini_training/` (`scontrino_JP_01..54.jpg`, il 14 è stato rimosso dall'utente) + ground truth tabellare in `scontrini_training/scontrini_analisi.csv`. Obiettivo: misurare l'accuratezza del parser su scontrini reali e affinare le regole (importo, data, valuta, esercente, voto lingua). Vincolo invariato: ML Kit non è eseguibile su questa macchina e **nessun device Android era collegato** (`flutter devices` 2026-08-20) → il testo si ottiene per trascrizione fedele delle foto; la verifica con OCR reale on-device resta in fase 6b.

- [x] Trascritte tutte le immagini in fixture `.txt` (riga per riga, layout fedele) in `test/fixtures/real_receipts/jp/` — 54 fixture (le 14 preesistenti + 40 nuove)
- [x] Per ogni fixture, `.expected.json` con ground truth dal CSV (importo, valuta, data, esercente, lingua)
- [x] Baseline sulle 54 fixture: **212/216 = 98,1%** — 4 KO: `SUPERMARKET` come fornitore (JP_24), riga intestatario `___様` (JP_25), data con anno a 2 cifre `26/07/25` (JP_31), `合計 8.858` + `端数処理 ¥-8` (JP_45)
- [x] Analisi errori per causa e fix chirurgici in `receipt_parser.dart` / `language_profiles.dart`: pattern data `yy/mm/dd` solo per il profilo ja, `roundingKeywords` (`端数処理`) applicati al totale keyword, righe-rumore fornitore (categoria generica, blank intestatario, `明細`, frasi di cortesia)
- [x] **Secondo harness, su testo degradato** (`test/real_receipts_noise_accuracy_test.dart`): applica agli stessi scontrini gli errori ML Kit già misurati on-device (`¥`->`4`, migliaia spezzate, full-width, `ー`->`-`, `O`->`口`, `加`->`カ`, logo con `#`) più le fusioni di righe di `reconstructReadingOrder`, su 40 degradazioni diverse per scontrino. Nessuna cifra viene mai cambiata in un'altra cifra: la ground truth resta sempre recuperabile.
- [x] Fix guidati dall'harness rumoroso: keyword valutata sul **proprio span** invece che sull'intera riga (una riga fusa `合計 ¥880 お預り ¥1.000` non viene più scartata), token di codice (`ARC00`, `T90210…`) e orari (`17:38`) esclusi dagli importi, riga-titolo esclusa dal fallback di colonna, recupero del nome negoziante prima di un campo metadato / dopo una frase di cortesia o un'intestazione documento
- [x] Fixture promosse a regression test permanenti (due suite dedicate, gate `>= 95%`)
- [ ] Documentare regole nuove/modificate in `Specifiche.md` — da fare alla prossima revisione della spec

**Verifica fase 6c** (eseguita 2026-08-20)
- [x] Trascrizioni pulite: **216/216 = 100%** (importo 54/54, data 54/54, valuta 54/54, fornitore 54/54)
- [x] Testo degradato ML Kit, 40 seed x 54 scontrini: **8635/8640 = 99,9%** (5 KO residui, tutti fornitore: banner reclutamento fuso in JP_49, nome perso in 2 seed su JP_25)
- [x] `flutter test` verde (467 test) + `flutter analyze` zero issue
- [x] **Accuratezza con OCR ML Kit reale, misurata 2026-08-25** (device OnePlus CPH2173, `integration_test/mlkit_ocr_accuracy_test.dart` sulle 53 foto): charAcc media **77,2%**, field accuracy **179/212 = 84,4%** (importo 47/53, data 51/53, valuta 51/53, fornitore 30/53). La misura sul testo pulito e su quello degradato sopravvalutava: il testo ML Kit vero è molto più rumoroso del modello.
- [x] **Regressione trovata dal confronto A/B col parser pre-hardening** (`52b46c4`, stesso testo ML Kit rigiocato): l'hardening di `55d2a2a` aveva portato l'importo da **46/53 a 43/53**. Causa radice: `_isCodeTail` (introdotta per scartare `ARC00`/`T9021001013831`) rifiutava ogni cifra preceduta da lettera latina, ma ML Kit rende il segno `¥` come una **`Y` o `F` isolata** (`合計 F544`, `お買上計 Y1,626`) su 13 scontrini su 53: il totale veniva scartato e il fallback pescava la cifra sbagliata. Fix in `receipt_parser.dart` (v0.14.1): una `Y`/`F` isolata prima delle cifre è un glifo valuta, non un prefisso di codice; i codici veri restano esclusi (test di regressione in `receipt_parser_test.dart`). Importo **43 → 47/53**, totale **179/212 = 84,4%**, verificato di nuovo sul device.
- [x] Regola `¥`→`Y`/`F` aggiunta al modello di rumore di `real_receipts_noise_accuracy_test.dart`: era l'errore sistematico che mancava, ed è il motivo per cui il gate al 99,9% non vedeva la regressione. Verificato che senza il fix la suite rumorosa ora fallisce.
- [x] **Obiettivo 95% raggiunto: 84,4% → 95,3% (202/212) su ML Kit reale, device OnePlus CPH2173, 2026-08-25, v0.15.0.** Per campo: importo **52/53**, data **52/53**, valuta **53/53**, fornitore **43/53**. Metodo: i testi ML Kit catturati dal log del device sono deterministici per foto, quindi sono stati rigiocati host-side (`MLKIT_DIR`/`EXPECTED_DIR`) per iterare in secondi, e ogni risultato è stato riconfermato sul device. Ground truth: `scontrini_training/scontrini_analisi.csv` — verificata riga per riga contro gli `*.expected.json` (importo/data/valuta coincidono su tutti e 53).
- [x] **Riparazione glifi nei numeri** (`repairJaDigits`, solo script ja): ML Kit dentro un importo scambia `1`→`l`/`I`, `0`→`O`/`o` (`合計 ¥l, O95`) e `¥`→`$` (`$2,178`); una lettera vale come cifra solo se cifre/separatori/`¥` la circondano, così `REGO2` e `No O 0 2` restano codici. `_splitThousands` generalizzata: ricongiunge il gruppo delle migliaia ovunque cada lo spazio (`¥6,0 50`, non solo `¥1, 489`). Risolve importo 32/40/49/50 e valuta 25/46.
- [x] **Token amputato**: un numero che inizia con la virgola (`合計 キ,780` per `¥17,780`) ha perso le cifre iniziali e non è un importo — la keyword successiva o il fallback ritrovano la copia intatta. Risolve importo 43.
- [x] **Data ISO con trattino raddoppiato** (`2026-07--24`): il trattino è un glifo sottile che ML Kit stampa due volte. Risolve data 23.
- [x] **Selezione del fornitore riscritta** (fornitore 30/53 → 43/53). La riga 1 è il LOGO in carattere stilizzato, che ML Kit sbaglia molto più del nome stampato sotto in carattere normale. Marcatori impossibili in un nome vero → riga scartata: latino incollato a hiragana (`UMIZじ`), CJK dentro una parola latina (`LAW日口N`), una lettera latina isolata in coda a un run CJK (`平禄寿言a`), minuscola a inizio parola seguita da maiuscola in una riga altrimenti maiuscola (`BOOK-oF`), barra verticale da grafica (`日高屋バイト |検索`). In più: dust iniziale esteso a parentesi/asterischi (`*おかしのまちおか`, `」KAWARAYA`), `0`→`O` fra lettere latine (`B0OKOFF`), hiragana isolata davanti a un nome katakana (`でヨークベニマル`), `頁収` come lettura errata di `領収`, e recupero del nome davanti a un'intestazione documento su riga fusa (`MEGA 領収書` → `MEGA`, solo con separatore fra i due).
- [x] **Regola logo→nome in chiaro** (`HARD-OF` → `ハードオフ宇都宮駅東店`): quando il primo candidato è una riga intera solo-latina e il successivo porta CJK, vince il secondo. Bilancio misurato: **+3 scontrini (26/30/53), −1 (JP_10**, dove anche la riga in chiaro è corrotta: `宇者都宮` per `宇都宮`**)**. [NON-BLOCKING] Effetto collaterale da valutare: su 7 scontrini l'app ora mostra il nome giapponese invece del brand latino (`かわらや宇都宮店` invece di `KAWARAYA`, `ND宇都宮中央` invece di `NewDays`) — entrambe le rese sono ammesse dalla ground truth, ma per una nota spese italiana il brand latino è più leggibile. Invertire la preferenza costa 2 campi.
- [ ] **Tetto residuo: 10 KO su 212, 8 dei quali sono corruzione del nome carattere per carattere** (`健太鼓子`/`健太子`/`健太骸子` per `健太餃子`, `後河屋` per `駿河屋`, `1ニオン コマースに` per `ユニオン コマース`, `趣りんく、` per `麺屋りんく`, `PIYO P22A` per `PIYO PIZZA`, più JP_10). La riga giusta viene già scelta: quello che manca è un glifo che ML Kit non ha mai emesso, quindi nessuna regola di selezione può recuperarlo. Unica strada reale: **lessico esercenti + match fuzzy**, alimentato dai fornitori già salvati nel DB dell'app (l'utente torna sugli stessi negozi). Su questo dataset varrebbe ~1 campo, ma cresce con l'uso.
- [ ] JP_51 (slip carta, charAcc 56,8%) resta KO su importo e data: il totale `*3, 700` non ha keyword riconoscibile (`TuTAL AMoUNI`) e la data è `20264| 06月 13|`. Recuperabile solo con regex tagliate su quello scontrino → non fatto di proposito.

## Fase 6d — Crop immagine post-scatto ▢

> Recupera il pulsante "✎ Edit" / `image_cropper` rimandato in fase 4: possibilità di ritagliare la foto **dopo lo scatto e prima del salvataggio e del parsing OCR**, così il parser lavora solo sull'area dello scontrino. Vale per tutti i percorsi di acquisizione (scanner ML Kit, camera fallback, galleria).

- [ ] Integrare `image_cropper` (o equivalente) nel punto di aggancio previsto in `receipt_capture_service.dart` (commento `[NON-BLOCKING]` fase 4)
- [ ] Flusso: scatto/selezione → schermata crop (rotazione + ritaglio libero) → conferma → compressione/salvataggio (`photo_service.dart`) → OCR/parsing sull'immagine croppata
- [ ] Crop opzionale e skippabile: annulla/salta → si procede con l'immagine originale, mai bloccare il flusso
- [ ] Percorso scanner ML Kit: crop già incluso nello scanner → schermata crop aggiuntiva non riproposta (evitare doppio crop); percorsi camera/galleria: crop sempre offerto
- [ ] Possibilità di ri-croppare dal form di conferma prima di "riprova OCR" (il retry usa l'immagine croppata)
- [ ] Test: unit/widget test del flusso capture→crop→salva e capture→skip crop→salva (crop UI fake/mockata, pipeline compressione già unit-testata)

**Verifica fase 6d**
- [ ] Widget test verdi su entrambi i rami (con e senza crop); `flutter analyze` zero issue
- [ ] Su dispositivo reale (quando disponibile, con fase 6b): scatto → crop → OCR sul ritaglio → form pre-compilato

## Fase 6e — Supporto scontrini polacchi (PLN) ✅ 2026-08-25

> Estensione del parser al polacco, riusando quanto imparato sugli scontrini giapponesi (fase 6c): keyword valutata sul proprio span, varianti di glifo che l'OCR sbaglia in modo sistematico, righe di intestazione riconosciute come rumore. Nessuna foto reale disponibile: le fixture sono modellate sul `paragon fiskalny` standard, una delle quali simula l'output ML Kit (righe fuse, diacritici persi). La misura on-device resta da fare quando ci saranno scontrini veri.

- [x] Profilo `pl` in `language_profiles.dart`: keyword totale in ordine di specificità (`suma pln`, `razem pln`, `kwota pln`, `do zapłaty`, poi `razem`/`suma`/`łącznie`/`kwota`), formato `commaDecimal`, valuta di default `PLN`, date ISO (`2026-07-14`) prima delle forme puntate/slash
- [x] Negative keyword tarate sul paragon: `ptu` (l'IVA polacca) uccide `SUMA PTU` senza toccare `SUMA PLN` perché la keyword possiede solo i numeri prima dell'etichetta negativa successiva; `podsuma`/`częściowa` (subtotali che contengono `suma`), `gotówka`/`reszta` (contante versato e resto), `rabat`, `nip`, `tel`
- [x] Valuta: `zł`/`PLN` riconosciuti da `inferCurrencyFromText`. La `ł` è un glifo sottile che ML Kit rende come `l`, quindi è la cifra davanti al simbolo a distinguere `45,00 zl` da una parola che finisce in `zl` (`\b` non serve: in Dart `\w` è ASCII e non vede mai `ł` come lettera)
- [x] Migliaia separate da spazio (`1 234,56`, standard sui POS polacchi) ricongiunte in `normalizeOcrText`: un solo spazio, gruppo di 3 cifre e coda di 2 decimali, così una colonna quantità allineata con più spazi resta intatta
- [x] Intestazione del paragon riconosciuta come rumore per il fornitore: codice postale polacco (`00-950`, che `\d{5}` non vedeva), prefissi via `ul./al./os./pl.`, `NIP`, e `PARAGON`/`RACHUNEK`/`FAKTURA` fra le intestazioni documento
- [x] Integrazione: `pl` selezionabile come lingua della trasferta, incluso nell'enum dello schema Claude, e `PLN` → hint `pl` in `effectiveLinguaHint` (il polacco resta sul riconoscitore latino di ML Kit: l'hint serve al voto lingua del parser, non al motore OCR). PLN è pubblicata dalla BCE → conversione in EUR già funzionante senza modifiche
- [x] **Confine di parola nel matching keyword** (vale per tutte le lingue latine/cirilliche, trovato mentre si aggiungeva il polacco): il matching avviene sulla riga compattata senza spazi — scelta corretta per il giapponese (`合  計`) ma che su alfabeti con spazi fa matchare una keyword dentro una parola più lunga. `suma` (PL) sta dentro `conSUMAzione` e uno scontrino italiano senza la parola "totale" veniva letto come polacco; simmetricamente `tel` (negativa) sta dentro `Hotel`, e su una fattura d'albergo è proprio la riga del totale. Fix: gli indici del match vengono rimappati sulla riga originale e la keyword vale solo se non ha una lettera adiacente (le cifre non contano: `SUMA45,00` resta valido). Le keyword CJK sono esenti per costruzione. Applicato a keyword positive, negative e bonus di voto lingua
- [x] Fixture di regressione in `test/fixtures/receipts/pl/` (supermercato, ristorante, taxi + versione ML Kit degradata) e test unitari su keyword, valuta, data, fornitore
- [x] Nessuna regressione sul giapponese, verificata per ablazione (regole PL disattivate una a una e rimisurate): trascrizioni pulite **216/216**, testo degradato **8632/8640 = 99,9%**, identiche prima e dopo
- [ ] Misura su scontrini polacchi reali (device), come fatto per il giapponese: senza foto vere l'accuratezza qui non è misurata, solo modellata

## Fase 7 — Export CSV / PDF ▢
- [x] `csv_export_service.dart`: export flat spese trasferta (tutte le colonne, separatore compatibile Excel IT)
- [x] `pdf_export_service.dart`: copertina (trasferta, periodo, totali) + tabella spese + pagine foto scontrini
- [x] Condivisione via share sheet Android (`share_plus`, `Share.shareXFiles` — verificare parametri sul changelog della versione installata)
- [x] Voci export nel menu del dettaglio trasferta
- [x] Unit test generazione CSV (contenuto e escaping)

- [x] **Conversione EUR estesa a tutte le valute + riepilogo per valuta** (richiesta utente, fatto 2026-07-30, v0.12.0+17). Spec: `docs/superpowers/specs/2026-07-30-conversione-tutte-le-valute-design.md`, piano: `docs/superpowers/plans/2026-07-30-conversione-tutte-le-valute.md`. Cosa è cambiato:
  - `exchange_service.dart` usa **due fonti in catena**: BCE/frankfurter primaria (tassi citabili in un rimborso), `@fawazahmed0/currency-api` via jsDelivr come fallback per le 10 valute fuori BCE (RSD, AED, KWD, QAR, SAR, TWD, VND, ALL, BAM, MKD). Un 404 della BCE marca la valuta come non coperta e la salta per il resto della sessione; un errore di rete resta ritentabile.
  - **Fix contestuale**: `api.frankfurter.app` rispondeva 301 verso `api.frankfurter.dev/v1/` (funzionava solo perché Dart segue i redirect, con un round-trip sprecato a ogni conversione). Ora si punta direttamente al dominio nuovo.
  - Nuovo `ValutaBreakdown` (`lib/data/models/`) + `SpesaRepository.breakdownPerValuta`: una query al posto di tre. Header dettaglio, copertina PDF e sintesi CSV mostrano per ogni valuta **n. spese + totale originale + ≈EUR** al posto della nota "esclude N spese non convertite".
  - Nuovo `ConversionBackfillService` + pulsante **"Ricalcola"** nel dettaglio trasferta (visibile solo se restano spese senza conversione): converte in blocco le spese con `importo_eur` NULL e riporta l'esito in SnackBar.
  - Nessuna modifica di schema DB (`dbVersion` resta 1). 451 test verdi, `flutter analyze` zero issue.
  - Limite residuo dichiarato: offline, o per date anteriori al 2024 (storico della fonte secondaria), `importo_eur` resta NULL — ma nessuna valuta è più esclusa *per costruzione*.
  - Fuori scope volutamente: migrazione di `trip_card`/lista trasferte al breakdown, colonna "fonte del tasso" in DB (richiederebbe migrazione di schema), nuovo layout grafico PDF (mockup C blu).

- [x] **Nuovo layout grafico del PDF** (mockup "C — Dashboard" in palette blu, scelto dall'utente 2026-07-30; fatto 2026-07-30, v0.13.0+18). Copertina: badge + titolo + chip luogo/date, riga di 3 stat card (totale ≈EUR, n. spese, giorni), card "per valuta" (dati della modifica A), card "per categoria" con barre proporzionali. Tabella: header blu ripetuto su ogni pagina, righe a zebra, riga totale blu. Pagine foto: card bianche con riquadro foto arrotondato e didascalia. Palette in `_Palette` dentro `pdf_export_service.dart` (colori da stampa, volutamente separati dal tema Material dell'app).
  - **Scostamento dal mockup, motivato:** la tabella spese non ha la card con angoli arrotondati. Deve impaginarsi su più pagine (`MultiPage`) e un `ClipRRect` non può attraversare un salto pagina: forzerebbe tutta la tabella su una pagina sola mandandola in overflow.
  - **Bug trovato e corretto** (emerso generando un PDF campione, non dai test): il simbolo AED `د.إ` è in scrittura araba e i font Noto inclusi (latino + JP) non hanno quei glifi → gli importi AED uscivano come caselle vuote. Riguardava anche KWD, QAR, SAR. Fix: `PdfFonts.valuteSenzaSimbolo` legge la cmap dei font veri e `formatValutaPdf` ripiega sul codice ISO (`AED 45,00`) solo per le valute il cui simbolo non è disegnabile. Nessun font nuovo aggiunto (il JP pesa già 9,4 MB). `formatValuta` resta invariato: a schermo il font di sistema disegna l'arabo senza problemi.
  - **Verifica visiva ESEGUITA** (2026-07-30, v0.13.1+19): il PDF è stato aperto sul device reale (OnePlus CPH2173, visualizzatore Drive) dopo build+install. La copertina è corretta: 3 stat card, blocco per valuta con `AED · 1 spesa · AED 45,00`, 7 barre per categoria, nota finale. Tabella con header blu ripetuto, zebra e riga totale.
  - 🐞 **BUG-05 — copertina PDF troncata sotto il titolo** (trovato 2026-07-30 *solo* guardando il PDF, corretto in v0.13.1). `_statRow` usava `pw.Row(crossAxisAlignment: stretch)` dentro una `Column`: nel package `pdf` i figli di una Column ricevono altezza **non limitata**, quindi `stretch` risolve a un box infinito → la Row non disegnava nulla **e** azzerava lo spazio di tutti i widget successivi. Risultato: copertina con solo badge, titolo e chip; stat card, blocco valute e barre spariti. **Il PDF si generava senza eccezioni, con le 4 pagine attese e byte non vuoti: nessun test esistente poteva accorgersene.** Fix: rimosso `stretch` (le card sono comunque di pari altezza). Guard aggiunto: `cover and table both render their content` in `test/export/pdf_export_service_test.dart` decomprime i content stream e conta gli operatori di testo per pagina — verificato che fallisce reintroducendo il bug (copertina 12 operazioni contro 70).
  - Corretto anche l'avviso `Helvetica-Oblique has no Unicode support`: la nota in corsivo ripiegava su un font built-in senza Unicode (non spediamo un Noto corsivo). Corsivo rimosso.
  - Gotcha da ricordare: **`CrossAxisAlignment.stretch` in una Row dentro una Column del package `pdf` rompe silenziosamente il resto della pagina.** La Row delle pagine foto può tenerlo perché sta direttamente in una `Page` (altezza limitata).

**Verifica fase 7**
- [ ] Export di una trasferta reale con foto: PDF apribile e completo, CSV importabile in Excel/Calc, share sheet funzionante — **parziale (2026-07-30)**: su device reale il menu "Esporta PDF" produce `NotaSpese_test_2026-07.pdf` e apre lo share sheet correttamente; il *contenuto* del PDF è stato verificato aprendo un export dello stesso codice nel visualizzatore Drive. Restano da provare: CSV in Excel/Calc e l'invio effettivo tramite uno share target.
- [x] **Occhio umano sul PDF**: fatto 2026-07-30 — ha trovato BUG-05 (copertina troncata), che nessun test automatico aveva rilevato.

## Fase 8 — Impostazioni + Backup/Restore ✅
- [x] Schermata Impostazioni completa (`lib/ui/impostazioni/impostazioni_screen.dart`, sostituisce `ImpostazioniMinimal`): motore OCR default (ML Kit / Claude Vision), API key, cartella foto, qualità JPG, spazio usato, backup, toggle tassi online, versione app
- [x] Setting qualità JPG: slider 50–90 (default 70), persistito in `SharedPreferences`, letto da `photo_service.dart`; nota UI "vale per le nuove foto"
- [ ] ~~Gestione modello IA locale~~ — **fuori scope fase 8** (decisione 2026-07-25): nessun `LocalAiOcrService` esiste, gate benchmark fase 5 non superato → nessuna UI di download/stato/eliminazione, l'indicatore spazio copre solo la cartella foto
- [x] API key Claude Vision: inserimento/modifica mascherata, `flutter_secure_storage` (invariato da fase 5)
- [x] Scelta directory foto con migrazione file esistenti (`PhotoDirMigrationService`, dialog "Migra ora"/"Annulla": i path in DB sono relativi alla base dir, cambiare cartella senza spostare le foto le renderebbe invisibili → nessuna opzione "lascia dove sono")
- [x] Indicatore spazio usato cartella foto (`PhotoDirUsage`: conteggio file + MB, ricalcolo on-demand)
- [x] `backup_service.dart`: zip `nota_spese.db` + cartella foto → share sheet; trigger manuale con progress
- [x] Restore da zip: estrazione in temp → validazione schema DB → swap con `.bak` + rollback → dialog "riavvia l'app" (no `RestartWidget`, decisione 2026-07-25)
- [x] Interfaccia `BackupService` con stub `uploadToDrive()` per v1.1 (lancia `UnimplementedError`)
- [x] Versione DB: hook `onUpgrade` no-op in `db_helper.dart` così un futuro bump non rompe le install esistenti (`dbVersion` resta 1: schema invariato in fase 8)

**Verifica fase 8**
- [ ] ~~Ciclo completo su emulatore~~ — **SKIP esplicito** (nessun emulatore su questa macchina, gotcha `CLAUDE.md`): compensato da `test/backup_service_test.dart` (create + restore valido/DB invalido/zip corrotto/rollback), `test/photo_dir_migration_test.dart` e `test/impostazioni_screen_test.dart`; collaudo reale rimandato a device fisico (stile fase 6b)
- [ ] API key salvata sopravvive al riavvio e non compare in SharedPreferences → verificabile solo su device (invariato da fase 5)

## Fase 9 — Archivio, polish, release ▢
- [ ] Archivio: filtro per anno/mese, ricerca per nome/luogo
- [ ] Stati vuoti, loading e errori uniformi su tutte le schermate
- [ ] Toast/SnackBar coerenti per ogni azione (salva, elimina, backup, export)
- [ ] Icona app + splash + nome app definitivo
- [ ] Passata di accessibilità minima (contrasti, tap target ≥48dp, `Semantics` su azioni chiave)
- [ ] Test end-to-end manuale del flusso core: scatto → OCR → conferma → salva → export PDF/CSV
- [ ] `flutter build apk --release` firmato, installazione su dispositivo reale
- [ ] `Readme.md` aggiornato (screenshot, funzionalità v1.0)

**Verifica fase 9 (release)**
- [ ] Tutte le checkbox delle fasi precedenti spuntate
- [ ] `flutter analyze` zero issue, `flutter test` tutto verde
- [ ] APK release funzionante su dispositivo reale

---

## v1.1 — Backlog (fuori scope v1.0)
- [ ] Plugin contrast/brightness nel flusso camera (aggancio già previsto in fase 4)
- [ ] Backup automatico Google Drive (`google_sign_in` + `googleapis`, stub `uploadToDrive()` pronto)
- [ ] IA locale, upgrade qualità: fine-tuning **Gemma 3 270M** (QLoRA) su dataset scontrini proprio → ~300 MB on-device, più veloce e potenzialmente più preciso del generalista 1B (vedi studio §C2) — da attivare se il gate fase 5 fallisce o se JA/SR deludono
- [ ] VLM minimali classe SmolVLM (immagine→JSON diretto, senza ML Kit): da riguardare quando qualità OCR e runtime mobile/Flutter matureranno (studio v2, NO-GO attuale)
- [ ] PaddleOCR PP-OCRv4 **solo modello cyrillic** (~15 MB + integrazione nativa Paddle-Lite): solo se all'uso reale gli scontrini SR in cirillico risultano frequenti e il motore Claude non basta (vedi `docs/catena-detection-ocr.md`)
- [ ] Directory foto arbitraria via SAF (`content://` URI) — v1.0 limita a directory app-specific
- [ ] Strategia di migrazione DB formale (script per versione)
