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
- ⚠️ Limite: frankfurter copre solo le ~30 valute ECB: **RSD e AED senza conversione automatica** (campo EUR manuale); eventuale API alternativa → v1.1

**Verifica fase 6**
- [ ] Spesa JPY online → EUR auto compilato; in modalità aereo → campo vuoto editabile, nessun blocco — **SKIP esplicito** (ambiente Android incompleto, vedi gotcha in `CLAUDE.md`); compensata da unit + widget test con `MockClient`/fake
- [x] `flutter test` (252/252) + `flutter analyze` (zero issue) verdi (2026-07-19)

## Fase 6b — Collaudo su dispositivo reale + bugfix ▢

> Prima fase con l'app in mano all'utente: installazione dell'APK (build GitHub Actions) su dispositivo Android reale, uso in ambiente reale e fix dei bug rilevati. Recupera anche tutte le verifiche **SKIP esplicito** accumulate nelle fasi 0b-6 (ambiente Android incompleto sulla macchina dev).

- [ ] Installare l'APK release (artifact GitHub Actions, v0.7.0+7 o successiva) sul dispositivo reale
- [ ] Collaudo del flusso core: scatta scontrino → scanner/crop → OCR → form pre-compilato → salva → foto in lista → viewer → elimina
- [ ] Recupero verifiche SKIP delle fasi precedenti:
  - [ ] App parte senza crash, tema corretto (fase 0b)
  - [ ] CRUD trasferte completo senza crash (fase 2)
  - [ ] Spesa manuale: crea → lista → totali → modifica → elimina (fase 3)
  - [ ] Foto: scatto → salva → thumbnail → viewer → eliminazione file dal filesystem; API Document Scanner (beta) funzionante o fallback camera (fase 4)
  - [ ] OCR scontrino reale IT: form pre-compilato corretto; verificare limitazione script latino ML Kit su JA (decision point in `mlkit_ocr_service.dart`) (fase 5)
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
- [ ] **Nota post-fix BUG-01:** le spese già salvate restano con `importo_eur` NULL; vanno riaperte e ricalcolate a mano (pulsante "ricalcola" nel form spesa) perché rientrino nei totali.
- [x] **BUG-03 — Importo primario in EUR invece che nella valuta originale** (2026-07-21). L'app dava rilievo a un dato derivato e opzionale (`importo_eur`): senza conversione tutte le schermate mostravano `€ 0,00` pur avendo spese registrate. Fix: totali primari per valuta originale in header dettaglio e card lista, EUR come riga secondaria nascosta quando manca o quando è già l'unica valuta, categorie in valuta originale se la trasferta ne ha una sola, nota `esclude N spese senza conversione` sul totale complessivo. Spec `docs/superpowers/specs/2026-07-21-importo-primario-valuta-originale-design.md`. v0.8.0
- [x] **Ritaglio dopo lo scatto** (2026-07-21, v0.9.0): schermata di crop in-app tra cattura e OCR (`lib/ui/foto/crop_screen.dart` + `lib/services/photo/crop_service.dart`, Dart puro sopra il pacchetto `image`, nessuna dipendenza nativa). Il rettangolo parte sull'immagine intera: confermare senza trascinare non ricodifica il file. Il ritaglio vale sia per il testo passato all'OCR sia per la foto salvata. Spec: `docs/superpowers/specs/2026-07-21-crop-scontrino-design.md`.

**Verifica fase 6b**
- [ ] Flusso core completo eseguito su dispositivo reale senza crash né bug bloccanti
- [ ] Tutti i bug raccolti fixati o esplicitamente rimandati (con motivazione) a v1.1
- [ ] `flutter test` + `flutter analyze` verdi dopo i fix

## Fase 6c — Training e affinamento parser su scontrini reali (JP) ▢

> Dataset: 14 foto di scontrini giapponesi in `scontrini_training/` (`scontrino_JP_01..14.jpg`). Obiettivo: misurare l'accuratezza del parser fase 5 su scontrini reali e affinare le regole di riconoscimento (importo, data, valuta, esercente, voto lingua). Vincolo: ML Kit OCR non è eseguibile su questa macchina (gotcha ambiente Android in `CLAUDE.md`) → il testo si ottiene per trascrizione fedele delle foto (simulando l'output OCR, rumore incluso); la verifica con OCR reale on-device resta in fase 6b. Metodo estendibile in seguito ad altre lingue.

- [ ] Trascrivere ogni immagine in fixture `.txt` (riga per riga, layout e rumore fedeli allo scontrino) in `test/fixtures/receipts/training/jp/`
- [ ] Per ogni fixture, `.expected.json` con ground truth verificata a mano (importo, valuta, data, esercente, lingua)
- [ ] Baseline: eseguire il parser sulle 14 fixture e registrare l'accuratezza per campo (importo / data / valuta / esercente / lingua)
- [ ] Analisi errori: classificare i miss per causa (keyword totale mancante, formato data non coperto, decimali, voto lingua, rumore OCR)
- [ ] Affinare le regole in `receipt_parser.dart` / `language_profiles.dart` (es. keyword totale JA aggiuntive, pattern data, euristiche layout) — modifiche chirurgiche, zero regressioni sulle fixture esistenti
- [ ] Promuovere le 14 fixture a regression test permanenti (suite fixture esistente o file dedicato)
- [ ] Documentare regole nuove/modificate ed eventuali gotcha in `Specifiche.md` / `CLAUDE.md`

**Verifica fase 6c**
- [ ] Accuratezza post-affinamento sulle 14 fixture: importo ≥ 12/14, data ≥ 12/14, valuta 14/14 (JPY), lingua 14/14 — soglie riviste se il dataset reale si rivela più rumoroso del previsto (motivare)
- [ ] `flutter test` verde (fixture esistenti + nuove) + `flutter analyze` zero issue

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

## Fase 7 — Export CSV / PDF ▢
- [ ] `csv_export_service.dart`: export flat spese trasferta (tutte le colonne, separatore compatibile Excel IT)
- [ ] `pdf_export_service.dart`: copertina (trasferta, periodo, totali) + tabella spese + pagine foto scontrini
- [ ] Condivisione via share sheet Android (`share_plus`, `Share.shareXFiles` — verificare parametri sul changelog della versione installata)
- [ ] Voci export nel menu del dettaglio trasferta
- [ ] Unit test generazione CSV (contenuto e escaping)

**Verifica fase 7**
- [ ] Export di una trasferta reale con foto: PDF apribile e completo, CSV importabile in Excel/Calc, share sheet funzionante

## Fase 8 — Impostazioni + Backup/Restore ▢
- [ ] Schermata Impostazioni completa (layout dal mockup, estende il `SettingsService` minimale nato in fase 4/5): motore OCR default (ML Kit / IA locale se GO / Claude Vision), API key, cartella foto, qualità JPG (default 70%), spazio usato, backup, toggle tassi online, versione app
- [ ] Setting qualità JPG: slider/selettore (es. 50–90%), persistito in `SharedPreferences`, letto da `photo_service.dart`; nota UI "si applica alle nuove foto"
- [ ] Gestione modello IA locale: download on-demand (~529 MB, avviso Wi-Fi), stato/dimensione, pulsante elimina; l'indicatore spazio include il modello; opzione motore visibile solo a modello scaricato e gate fase 5 superato
- [ ] API key Claude Vision: inserimento/modifica, salvata con `flutter_secure_storage` (Android Keystore, mai in chiaro), mostrata mascherata
- [ ] Scelta directory foto con migrazione file esistenti (o avviso)
- [ ] Indicatore spazio usato cartella foto (conteggio file + MB)
- [ ] `backup_service.dart`: zip `nota_spese.db` + cartella foto → directory scelta/share sheet; trigger manuale con progress
- [ ] Restore da zip: estrazione su file temporanei → swap atomico → riapertura DB → reload UI via `RestartWidget` (vedi Specifiche §9)
- [ ] Interfaccia `BackupService` con stub `uploadToDrive()` per v1.1 (non implementato)
- [ ] Versione DB incrementabile in `db_helper.dart` (migrazione formale rimandata a v1.1)

**Verifica fase 8**
- [ ] Ciclo completo su emulatore: backup → cancella una trasferta → restore → dati e foto tornati, app coerente senza riavvio manuale (o con dialog riavvio)
- [ ] API key salvata sopravvive al riavvio e non compare in SharedPreferences

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
