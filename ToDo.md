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
- [x] Flusso camera: **ML Kit Document Scanner** come percorso principale (fallback automatico a `image_picker` camera su eccezione); `image_picker` camera/galleria selezionabili dal form ("Aggiungi foto"); pulsante "✎ Edit" / `image_cropper` **rimandato** (lo scanner croppa già; aggancio previsto)
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

## Fase 5 — OCR + parser multilingua ▢
- [ ] Interfaccia `OcrService` unica (input immagine → testo grezzo); i chiamanti non conoscono il motore
- [ ] `MlkitOcrService` (default, offline) — richiede `compileSdk 35` (già in fase 0)
- [ ] `receipt_parser.dart`: estrazione **importo** (valore maggiore + keyword totale/total/合計/итого/gesamt), **fornitore**, **data** (regex per-lingua, fallback data odierna — mai bloccare il flusso)
- [ ] Lingue parser: IT · EN · JA · SR · DE (+ pattern comuni); hint da `lingua_default` trasferta
- [ ] Gap cirillico ML Kit (SR): instradare scontrini in cirillico verso il motore Claude quando disponibile; messaggio chiaro se offline senza Claude (vedi `docs/catena-detection-ocr.md`)
- [ ] Inferenza valuta dalla lingua/paese (JA→JPY, SR→RSD, EN-UK→GBP, CH→CHF, US→USD, area euro→EUR), override da impostazioni trasferta, correzione utente nel form
- [ ] Form di conferma pre-compilato con banner "Compilato dallo scontrino · verifica i dati" + indicazione motore usato (`ocr_engine` salvato)
- [ ] `ClaudeOcrService` (opzionale): Vision API con modello **`claude-haiku-4-5`** (~$0,2-0,35/mese a 90 scontrini) + **structured outputs** (`output_config.format` con `json_schema` dei campi → JSON garantito valido, salta il parser); stesso prompt/schema del motore locale per confronto; disabilitato se API key assente; se offline → fallback automatico a ML Kit. Per poterlo testare in questa fase: campo API key **minimale** in Impostazioni via `flutter_secure_storage` (anticipo — la schermata completa è in fase 8)
- [ ] **Gate benchmark IA locale comparativo** (primo task del blocco, da studio 0a v2): su dispositivo reale con 3-5 scontrini veri — **Gemma 3 1B int4** (primario) e **Qwen2.5 1.5B** sulle fixture JA/SR (stesso runtime `.task`, provarli entrambi costa ~zero); riferimento qualità: stesso set su Claude Haiku 4.5. Criteri: latenza mediana ≤10 s, no OOM, importo+data corretti ≥80% su IT/EN. Falliti tutti → motore nascosto, fine-tune 270M in valutazione v1.1
- [ ] `LocalAiOcrService` (se gate superato): OCR ML Kit → Gemma 3 1B via `flutter_gemma` → JSON campi; output non valido → fallback parser regex, mai bloccare
- [ ] Prompt few-shot versionato (`local_ai_prompt.dart`) con esempi per lingua, validato dalle stesse fixture del parser
- [ ] (Opzionale) Gemini Nano via ML Kit Prompt API: se `checkFeatureStatus()` disponibile sul device → usarlo senza storage aggiuntivo (bonus, non requisito)
- [ ] Selettore motore: impostazione globale (default ML Kit) + override per singolo scatto PRIMA dello scatto (bottom sheet) o nel form di conferma ("riprova con altro motore") — la UI del Document Scanner è di Play Services, non personalizzabile; opzione IA locale visibile solo se implementata (`ocr_engine` = 'local_ai')
- [ ] Progress OCR fullscreen durante il riconoscimento
- [ ] **Suite fixture**: scontrini campione `.txt` per lingua in `test/fixtures/receipts/` + unit test importo/fornitore/data (l'utente fornisce directory immagini campione per test manuali)

**Verifica fase 5**
- [ ] `flutter test` parser verde su tutte le lingue fixture
- [ ] Su dispositivo: scatto scontrino reale → form pre-compilato corretto (almeno IT)
- [ ] Con API key assente: Claude Vision non selezionabile; offline: fallback a ML Kit

## Fase 6 — Multi-valuta / conversione EUR ▢
- [ ] `exchange_service.dart`: conversione via `frankfurter.app` (no key), timeout breve, mai bloccante
- [ ] Al salvataggio online: `importo_eur` + `tasso_cambio` valorizzati silenziosamente, badge **AUTO** nel form
- [ ] Offline o preferenza utente: campo EUR editabile manualmente o lasciabile vuoto; pulsante ricalcolo manuale
- [ ] Toggle "Tassi di cambio online" in Impostazioni
- [ ] Totali trasferta: somma in valuta originale + conversione EUR se disponibile (spese senza EUR escluse dal totale EUR, indicarlo)
- [ ] Unit test conversione con http mockato (successo, timeout, offline)

**Verifica fase 6**
- [ ] Spesa JPY online → EUR auto compilato; in modalità aereo → campo vuoto editabile, nessun blocco
- [ ] `flutter test` + `flutter analyze` verdi

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
