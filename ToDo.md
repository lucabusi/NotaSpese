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

**0b — Setup progetto**
- [ ] `flutter create` (org, nome pacchetto) nel repo; target Android; `minSdkVersion 33`, `compileSdk 35`, `ndkVersion "27.0.12077973"` in `android/app/build.gradle`
- [ ] `.gitignore` Flutter completo (build/, .dart_tool/, ecc.)
- [ ] `analysis_options.yaml` con `flutter_lints`
- [ ] Struttura cartelle `lib/` come da `Specifiche.md` (core/, data/, services/, ui/) — file placeholder minimi
- [ ] `lib/version.dart` con costante versione app
- [ ] Tema Material 3 in `core/theme/app_theme.dart`: token colore, Plus Jakarta Sans (`google_fonts`), Material Symbols Rounded — dal Design System in `Specifiche.md`
- [ ] Dipendenze fase 0-2 aggiunte con `flutter pub add` (versioni più recenti compatibili)

**Verifica fase 0**
- [x] `docs/fattibilita-ia-locale.md` esiste con verdetto GO/NO-GO motivato
- [ ] `flutter analyze` → zero issue
- [ ] App vuota con tema si compila e parte su emulatore

## Fase 1 — Data layer ▢
- [ ] Modelli `Trasferta`, `Spesa`, `Foto` (fromMap/toMap, campi come da DDL in `Specifiche.md`)
- [ ] Enum `Categoria` (pranzo·cena·colazione·trasporto·taxi·hotel·parcheggio·carburante·telefono·altro) con icona e label
- [ ] Enum valute supportate (EUR, JPY, USD, GBP, CHF, RSD, AED, SGD, …) — nessuna API per la lista; no HRK (kuna → EUR dal 2023)
- [ ] `db_helper.dart`: apertura DB, `PRAGMA foreign_keys = ON` a ogni connessione, creazione schema, versione DB
- [ ] `TrasfertaRepository`: CRUD + archivia + **delete cascade esplicito in transazione** (file foto → record foto → spese → trasferta)
- [ ] `SpesaRepository`: CRUD, spese per trasferta raggruppate per data, totali per categoria e totale trasferta (valuta originale + EUR se disponibile)
- [ ] `FotoRepository`: crea/leggi/elimina record + eliminazione file fisici PRIMA del record
- [ ] Unit test repository con `sqflite_common_ffi` (CRUD, cascade, totali, FK attive)

**Verifica fase 1**
- [ ] `flutter test` verde
- [ ] `flutter analyze` → zero issue

## Fase 2 — Shell UI + CRUD trasferte ▢
- [ ] `home_shell.dart`: `NavigationBar` 3 tab (Trasferte attive / Archivio / Impostazioni)
- [ ] Lista trasferte attive: header con totale complessivo €, card trasferta (icona, nome, date, badge valuta, n. spese, totale) — `shared/widgets/trip_card.dart`
- [ ] Form crea/modifica trasferta: nome, luogo, date, valuta default, lingua default, note
- [ ] Dettaglio trasferta (scheletro): header totale, lista spese vuota, FAB `+`
- [ ] Azioni trasferta: archivia / ripristina / elimina (con conferma)
- [ ] Tab Archivio: lista `archiviata = 1`, badge ARCHIVIATA
- [ ] Controller `ChangeNotifier` per lista/dettaglio, collegati ai repository
- [ ] Stati vuoti (nessuna trasferta) con invito all'azione

**Verifica fase 2**
- [ ] Creare/modificare/archiviare/eliminare una trasferta su emulatore senza crash
- [ ] `flutter analyze` zero issue, test fase 1 ancora verdi

## Fase 3 — Spese (inserimento manuale) ▢
- [ ] Bottom sheet FAB `+`: "📷 Scatta scontrino" (disabilitato fino a fase 4/5) / "✏️ Inserimento manuale"
- [ ] Form spesa: importo originale + valuta, importo EUR opzionale, categoria chip-select, data (default oggi, date picker), fornitore, note
- [ ] Tastiera numerica custom (griglia 3×4) per importi
- [ ] `currency_picker.dart` searchable: filtro testo, valute frequenti in cima (EUR, USD, JPY, GBP, CHF, RSD, AED, SGD)
- [ ] Salvataggio/modifica/eliminazione spesa (con conferma)
- [ ] Dettaglio trasferta completo: spese raggruppate per data, totali per categoria con barre, totale live
- [ ] Unit test: calcolo totali per categoria e formattazione importi

**Verifica fase 3**
- [ ] Flusso completo su emulatore: nuova spesa manuale → appare in lista → totali aggiornati → modifica → elimina
- [ ] `flutter test` + `flutter analyze` verdi

## Fase 4 — Foto scontrino ▢
- [ ] Permessi runtime API 33+ (`CAMERA`, `READ_MEDIA_IMAGES`) in `AndroidManifest.xml` + richiesta a runtime; gestire rifiuto con messaggio
- [ ] Flusso camera: **ML Kit Document Scanner** (`google_mlkit_document_scanner`, detection+crop+deskew automatici via Play Services, no permesso camera in-app) come percorso principale; `image_picker` → anteprima come riserva (API scanner in beta); pulsante "✎ Edit" opzionale → `image_cropper` (ritocco manuale)
- [ ] Punto di aggancio previsto per plugin contrast/brightness (future option v1.1) nel flusso camera
- [ ] `settings_service.dart` **minimale** (nasce qui, non in fase 8): qualità JPG + directory foto su `SharedPreferences` — la schermata Impostazioni completa arriva in fase 8, ma il service serve già a `photo_service.dart`
- [ ] `photo_service.dart`: compressione JPG (qualità letta da `SettingsService`, default 70%, max 1920px lato lungo) + thumbnail 300px in `thumbnails/` — originale non conservato
- [ ] Directory foto: default storage interno app; configurabile in Impostazioni ma limitata a directory app-specific in v1.0 (vincolo scoped storage, `Specifiche.md` §2); path salvati **relativi** alla directory
- [ ] Form spesa: thumbnail foto se presente / area "Aggiungi foto" se assente; aggiunta foto anche a spesa manuale esistente
- [ ] Viewer foto fullscreen: zoom, share, elimina (con conferma)
- [ ] Eliminazione coerente: rimozione spesa → file foto+thumbnail eliminati prima dei record (già nel repository, verifica end-to-end)

**Verifica fase 4**
- [ ] Su dispositivo/emulatore con camera: scatto → crop → salva → thumbnail in lista → viewer → elimina spesa → file spariti dal filesystem
- [ ] `flutter analyze` + test verdi

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
