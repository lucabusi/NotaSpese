# Nota Spese in Trasferta — ToDo & Setup

## Stack scelto
- **Framework:** Flutter (Dart)
- **DB:** SQLite locale (`sqflite`)
- **State management:** `ChangeNotifier` + `ListenableBuilder` (built-in Flutter, no Riverpod)
- **OS sviluppo:** Windows + VS Code
- **Target:** Android
- **Contesto d'uso:** single-user, offline-first, ~1-2 trasferte/mese, 60-90 spese/mese

---

## 📦 Dipendenze (`pubspec.yaml`)
- se possibile utilizza le versioni piu recenti dei pacchetti

| Package | Scopo | Fase |
|---|---|---|
| `sqflite` | DB SQLite locale | 1 |
| `path_provider` | path storage app | 1 |
| `intl` | formattazione date/importi | 1 |
| `google_fonts` | Plus Jakarta Sans (design mockup) | 0 (tema in 0b) |
| `material_symbols_icons` | icone Material Symbols Rounded | 0 (tema in 0b) |
| `google_mlkit_document_scanner` | detection/crop/deskew scontrino (Play Services, ~0 MB) | 4 |
| `image_picker` | scatto foto / galleria (percorso di riserva) | 4 |
| `image_cropper` | crop + rotazione | 4 |
| `flutter_image_compress` | compressione JPG + thumbnail | 4 |
| `permission_handler` | permessi runtime API 33+ | 4 |
| `file_picker` | selezione zip per restore + destinazione backup (SAF) | 8 |
| `google_mlkit_text_recognition` | OCR offline (default) | 5 |
| `flutter_gemma` | IA locale: Gemma 3 1B on-device (vedi studio fattibilità) | 5 |
| `http` | Claude Vision API + frankfurter.app | 5/6 |
| `flutter_secure_storage` | API key in Android Keystore | 5 |
| `shared_preferences` | settings non sensibili | 4 |
| `csv` | export CSV | 7 |
| `pdf` + `printing` | export PDF | 7 |
| `share_plus` | share sheet Android | 7 |
| `archive` | zip backup DB + foto | 8 |
| dev: `sqflite_common_ffi` | test repository su desktop/CI | 1 |
| dev: `flutter_lints` | analisi statica | 0 |

> Versioni: da risolvere con `flutter pub add` al momento dell'implementazione (`flutter pub outdated` per verifica). Nessuna versione bloccata in questo documento.


> **Future option (v1.1):** aggiungere plugin contrast/brightness quando necessario — il punto di aggancio deve essere già previsto nel flusso Camera.
> **Future option (v1.1) — Backup Google Drive:** aggiungere `google_sign_in: ^6.2.1` + `googleapis: ^13.2.0` per upload automatico del backup su Drive.

### ⚠️ Note compatibilità — breaking changes

**`flutter_secure_storage` 9 → 10:**
Jetpack Security deprecato da Google; Android reimplementato con cipher custom (RSA OAEP + AES-GCM). `encryptedSharedPreferences` non più disponibile. Migrazione automatica gestita dal plugin (`migrateOnAlgorithmChange: true` di default). Per uso semplice key-value (come questo progetto) è trasparente. Non richiede modifiche al codice.

**`share_plus` 9 → 12:**
API `Share.shareXFiles()` è stabile. Verificare i parametri al momento dell'implementazione consultando il changelog della versione installata (`flutter pub changelog share_plus`). La funzionalità core (share di file su Android) non è cambiata.

**`google_mlkit_text_recognition` 0.13 → 0.15:**
Richiede `compileSdk 35` e `ndkVersion "27.0.12077973"` in `android/app/build.gradle`.

**Verifica versioni al momento dell'implementazione:**
```bash
flutter pub outdated
```
I package non aggiornati in questa lista (`path_provider`, `image_cropper`, `pdf`, `printing`, ecc.) potrebbero avere patch release più recenti. `flutter pub outdated` mostra il resolvable più aggiornato compatibile con il proprio SDK.

Dopo aver modificato `pubspec.yaml`:
```bash
flutter pub get
```

## 📁 Struttura progetto

```
lib/
├── main.dart                          # entrypoint: init DB, settings, runApp
├── app.dart                           # MaterialApp, tema, route, RestartWidget (restore §9)
├── version.dart                       # $Version app (bump a ogni modifica funzionale)
├── core/
│   ├── theme/app_theme.dart           # ThemeData Material 3 (vedi Design System)
│   ├── constants/categories.dart      # enum categorie + icona + label
│   ├── constants/currencies.dart      # enum valute ISO 4217 supportate
│   └── utils/formatters.dart          # date/importi via intl
├── data/
│   ├── models/
│   │   ├── trasferta.dart
│   │   ├── spesa.dart
│   │   └── foto.dart
│   ├── db/db_helper.dart              # open nota_spese.db (getDatabasesPath), PRAGMA foreign_keys=ON, schema version
│   └── repositories/
│       ├── trasferta_repository.dart  # CRUD + delete cascade in transazione
│       ├── spesa_repository.dart      # CRUD + totali per categoria
│       └── foto_repository.dart       # record foto + delete file fisici
├── services/
│   ├── ocr/
│   │   ├── ocr_service.dart           # interfaccia astratta (unica per tutti i motori)
│   │   ├── mlkit_ocr_service.dart     # default offline
│   │   ├── local_ai_ocr_service.dart  # IA locale: ML Kit + Gemma 3 1B (GO condizionato, gate fase 5)
│   │   ├── local_ai_prompt.dart       # prompt few-shot estrazione campi, per lingua
│   │   ├── claude_ocr_service.dart    # opzionale, richiede API key + rete
│   │   └── receipt_parser.dart        # parse multilingua IT/EN/JA/SR/DE
│   ├── currency/exchange_service.dart # conversione EUR via frankfurter.app
│   ├── photo/photo_service.dart       # compressione, thumbnail, storage, delete
│   ├── export/
│   │   ├── csv_export_service.dart
│   │   └── pdf_export_service.dart    # copertina + tabella + foto
│   ├── backup/backup_service.dart     # zip DB+foto, restore, stub uploadToDrive() (v1.1)
│   └── settings/settings_service.dart # SharedPreferences + flutter_secure_storage
└── ui/
    ├── shell/home_shell.dart          # Scaffold + NavigationBar 3 tab
    ├── trasferte/                     # lista, dettaglio, form trasferta + controller
    ├── spese/                         # form spesa, tastiera numerica + controller
    ├── camera/                        # flusso scatto, anteprima, progress OCR
    ├── foto/                          # viewer fullscreen
    ├── archivio/                      # trasferte chiuse + filtro anno/mese
    ├── impostazioni/                  # settings screen + controller
    └── shared/widgets/                # currency_picker, category_chips, trip_card, ecc.

test/
├── receipt_parser_test.dart           # fixture per lingua (componente più fragile)
├── repositories_test.dart             # sqflite_common_ffi in-memory
├── exchange_service_test.dart         # mock http
└── fixtures/receipts/{it,en,ja,sr,de}/*.txt
```

Regole:
- Un file = una responsabilità; file screen separati dai controller.
- Naming: `snake_case.dart`; controller = `<feature>_controller.dart`; screen = `<feature>_screen.dart`.
- Widget riusati da 2+ schermate → `ui/shared/widgets/`.

## 🏗️ Architettura — Layer

Tre layer, dipendenze solo verso il basso (UI → controller → service/repository → DB/filesystem). Nessun package DI: composizione manuale in `main.dart` (i costruttori ricevono le dipendenze).

**State management:** un `ChangeNotifier` (controller) per schermata/feature; la UI osserva via `ListenableBuilder`. Flusso unidirezionale: evento UI → metodo controller → repository/service → `notifyListeners()` → rebuild. Nessuno stato condiviso globale eccetto `SettingsService` (passato dove serve).

**Regole:**
- I controller non toccano mai `sqflite` o filesystem direttamente: solo repository/service.
- I service sono stateless e testabili in isolamento; `OcrService` è un'interfaccia unica — i chiamanti non sanno quale motore è attivo.
- Le operazioni multi-step distruttive (delete cascade, restore) vivono nel repository/service in transazione, mai nella UI.

### Presentation layer

Schermate principali
- **Lista trasferte** — home, badge totale €, ordinamento per data
- **Dettaglio trasferta** — lista spese, totali per categoria, FAB `+`
- **Inserimento spesa** — form + conferma OCR/IA per riconoscimento automatico
- **Export** — non è una schermata dedicata: voci nel menu del dettaglio trasferta → PDF (copertina + tabella + foto) e CSV, condivisione via share sheet Android
- **Archivio / search** — trasferte chiuse, filtro per anno/mese

### Feature layer
- **Camera & OCR** — flusso scontrino (vedi sotto)
- **Trasferte CRUD** — crea / modifica / archivia / elimina
- **Spese CRUD** — inserimento / edit / filtri / totali live
- **Export** — generazione PDF con foto allegate e CSV flat

### Data layer
Repository pattern sopra `sqflite` e filesystem locale

---

## 🎥 Flusso critico — acquisizione scontrino

Due percorsi di ingresso, entrambi arrivano allo stesso Form di conferma:

[A] Con foto (percorso principale)
ML Kit Document Scanner (detection bordi + crop + deskew automatici, UI Play Services)
  ├→ fallback/riserva: Camera (image_picker) → anteprima
  └→ [pulsante "✎ Edit" opzionale]
       └→ image_cropper (ritocco manuale crop + rotazione)
            └→ [future_option v1.1: contrast/brightness]
  └→ Compressione JPG (flutter_image_compress)
       ├→ Qualità: default 70%, configurabile in Impostazioni · dimensione max: 1920px lato lungo
       ├→ Output: file compresso in directory foto (default: storage interno app, configurabile in Impostazioni)
       └→ Thumbnail generato contestualmente (300px) per uso in lista UI
  └→ OCR (motore selezionabile)
       ├→ ML Kit offline    ← default, funziona senza rete
       ├→ IA locale         ← previsto in v1.0, subordinato a studio di fattibilità (fase 0)
       └→ Claude Vision API ← opzionale, richiede rete, più preciso
  └→ Parse multilingua (receipt_parser.dart)
       ├→ Lingue supportate: IT · EN · JA · SR · DE + altre comuni
       ├→ Campi estratti: importo, fornitore, data
       └→ Data: legge dallo scontrino → fallback data odierna
  └→ Form di conferma (campi pre-compilati, utente corregge e salva)

[B] Senza foto (inserimento manuale)
FAB "+" nel dettaglio trasferta → pulsante "✏ Inserimento manuale"
  └→ Form vuoto (nessun OCR, tutti i campi da compilare manualmente)
       └→ Salva spesa senza record in tabella `foto`

### Regole parse — data
1. Lettura dallo scontrino (regex + euristiche per-lingua)
2. Fallback automatico → data odierna
3. L'utente può sempre sovrascrivere nel form di conferma

### OCR — selezione motore
- Impostazione globale in **Settings** (`ML Kit` di default); selettore a 3 opzioni: ML Kit / IA locale / Claude Vision (IA locale visibile solo se lo studio di fattibilità dà esito positivo)
- Override per singolo scatto: la UI del Document Scanner è di Play Services e non è personalizzabile → l'override si sceglie PRIMA dello scatto (nel bottom sheet "Aggiungi spesa") oppure DOPO, nel form di conferma ("riprova con altro motore")
- Se selezionata l'API ma il dispositivo è offline → fallback automatico a ML Kit
- **IA locale sul dispositivo:** studio di fattibilità completato, **v2** (2026-07-15) → **`docs/fattibilita-ia-locale.md`**. Verdetto: **GO confermato** per l'architettura ibrida — OCR ML Kit (testo) → LLM locale via `flutter_gemma`/MediaPipe → JSON campi. **Shortlist modelli intercambiabili** (stesso runtime `.task`): **Gemma 3 1B int4** primario (~529 MB), **Qwen2.5 1.5B** riserva per JA/SR (~1-1,6 GB). Modello scaricato on-demand dalle Impostazioni, mai bundlato nell'APK; parser regex sempre come fallback. Gate vincolante in fase 5: benchmark comparativo su dispositivo reale (latenza ≤10 s, no OOM, importo+data ≥80% su IT/EN; riferimento qualità: Claude Haiku 4.5). NO-GO: VLM end-to-end Gemma 3n (~3 GB), SmolVLM 256/500M (qualità OCR e toolchain Flutter insufficienti); fine-tune Gemma 3 270M → backlog v1.1.
- **Motore Claude Vision API:** modello di default **`claude-haiku-4-5`** ($1/$5 per MTok → ~$0,2-0,35/mese a 90 scontrini) con **structured outputs** (`output_config.format`, `json_schema` dei campi) → JSON garantito valido, nessun parsing fragile. Upgrade opzionale a `claude-opus-4-8` per scontrini difficili.
- **API key Claude Vision** — inserita dall'utente nella schermata Impostazioni; salvata con `flutter_secure_storage` (Android Keystore, non SharedPreferences in chiaro)

### UI — inventario funzionale (dal mockup)

Riferimento di design: `Trasferte.dc.html` (importabile via claude_design MCP — https://api.anthropic.com/v1/design/mcp, auth `/design-login` — progetto https://claude.ai/design/p/f129b2b3-d819-44f2-ae0c-074c3733be54?file=Trasferte.dc.html).

> Elenco **descrittivo**: le checkbox operative con criteri di verifica sono SOLO in `ToDo.md` (fonte di verità unica per l'avanzamento).

- Bottom nav bar (3 tab: Trasferte attive / Archivio / Impostazioni)
- Lista trasferte con badge totale € — filtro per `archiviata = 0` / `archiviata = 1`
- Dettaglio trasferta con lista spese e totali per categoria (in EUR)
- FAB "+" con scelta: 📷 Scatta scontrino / ✏️ Inserimento manuale
- Form inserimento/modifica spesa: importo originale + `currency_picker.dart` (searchable, pre-compilato da OCR); campo EUR opzionale (auto via `frankfurter.app` se online, altrimenti editabile o vuoto); tastiera numerica, categoria chip-select, data auto oggi; thumbnail foto se presente / pulsante "Aggiungi foto" se assente
- Visualizzatore foto scontrino (full screen)
- Schermata Impostazioni: motore OCR default (ML Kit / IA locale / Claude Vision API — IA locale se fattibile); API key Claude Vision (via `flutter_secure_storage`); directory foto (default storage interno app); qualità JPG (default 70%, solo nuove foto); indicatore spazio usato dalla cartella foto; trigger backup manuale (zip DB + foto)
- Gestione permessi Android API 33+ (`CAMERA`, `READ_MEDIA_IMAGES`) a runtime


## 🎨 Design System (dal mockup `Trasferte.dc.html`)

Variante scelta: **Blu professionale** (Material 3). Il mockup interattivo (9 schermate) è la fonte di verità per layout e gerarchia visiva.

### Token colore
| Token | Valore | Uso |
|---|---|---|
| `primary` | `#2563EB` | FAB, bottoni, accenti, tab attiva |
| `primaryContainer` | `#EAF0FE` | sfondo icone/badge primari |
| `background` | `#F4F6FA` | sfondo schermate |
| `surface` | `#FFFFFF` | card, header, nav bar |
| `onSurface` | `#0F1729` | testo primario |
| `textSecondary` | `#5B6675` / `#8A94A3` | sottotitoli, label |
| `textTertiary` | `#97A1B0` / `#A3ACBA` | hint, sezioni uppercase |
| `outline` | `#EDF0F5` / `#DFE4EC` | bordi card |
| `success` | `#13935A` su `#E9F7EF` | badge AUTO, conferme OCR |
| `archivio` | `#8A8030` su `#FBF3DA` | badge ARCHIVIATA |
| `surfaceDark` | `#0A0C11` | overlay camera/OCR/foto |

### Tipografia e forme
- Font: **Plus Jakarta Sans** (`google_fonts`), pesi 400–800; importi con `tabular-nums` (`FontFeature.tabularFigures()`).
- Icone: **Material Symbols Rounded** (`material_symbols_icons`).
- Radius: card 16–18, bottoni/campi 13–14, chip 12, bottom sheet 26 (top), FAB circolare.
- Elevazione bassa: bordo 1px + ombra leggera, stile "flat con profondità".

### Mappa componenti mockup → Flutter
| Mockup | Widget Flutter |
|---|---|
| Bottom nav 3 tab (pill attiva) | `NavigationBar` M3 personalizzata |
| Card trasferta (icona, badge valuta, totale) | `Card` custom in `shared/widgets/trip_card.dart` |
| Chip categoria selezionabili | `ChoiceChip` custom (icona + label) |
| Bottom sheet "Aggiungi spesa" (📷 / ✏️) | `showModalBottomSheet` |
| Tastiera numerica importo (griglia 3×4) | widget custom nel form spesa |
| Currency picker searchable | `shared/widgets/currency_picker.dart` (fullscreen, campo filtro) |
| Barre totali per categoria | `LinearProgressIndicator`-like custom su riga categoria |
| Overlay camera con cornice scontrino | percorso principale: UI Play Services del Document Scanner (non personalizzabile); overlay custom su `image_picker` solo nel percorso di riserva |
| Progress OCR (spinner fullscreen scuro) | screen/dialog modale durante riconoscimento |
| Toast conferme | `SnackBar` (floating, dark) |
| Banner verde "Compilato dallo scontrino" | `MaterialBanner`/container custom in cima al form |

### Regole UX
- Form spesa: importo sempre a fuoco all'apertura, tastiera numerica custom visibile.
- Campo EUR: badge **AUTO** se compilato da API, editabile sempre, mai bloccante.
- Data: precompilata (OCR → fallback oggi), modificabile con date picker.
- Foto nel form: thumbnail se presente, area tratteggiata "Aggiungi foto" se assente.
- Ogni azione distruttiva (elimina spesa/trasferta/foto) → conferma esplicita.

## 🗄️ Modello Dati

### Tabella `trasferte`

```sql
CREATE TABLE trasferte (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  nome           TEXT NOT NULL,
  luogo          TEXT,
  data_inizio    TEXT NOT NULL,              -- ISO 8601 'yyyy-MM-dd'
  data_fine      TEXT,                       -- NULL = in corso
  valuta_default TEXT NOT NULL DEFAULT 'EUR',-- ISO 4217, base per riconoscimento OCR
  lingua_default TEXT,                       -- hint parser: it|en|ja|sr|de (NULL = auto)
  archiviata     INTEGER NOT NULL DEFAULT 0, -- 0 attiva, 1 archiviata
  note           TEXT,
  created_at     TEXT NOT NULL               -- ISO 8601 con ora
);
```

### Tabella `spese`

```sql
CREATE TABLE spese (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  trasferta_id INTEGER NOT NULL REFERENCES trasferte(id),
  data         TEXT NOT NULL,                -- ISO 8601 'yyyy-MM-dd'
  categoria    TEXT NOT NULL,                -- enum categorie (sotto)
  fornitore    TEXT,                         -- estratto da OCR o manuale
  importo      REAL NOT NULL,                -- SEMPRE valuta originale
  valuta       TEXT NOT NULL,                -- ISO 4217
  importo_eur  REAL,                         -- NULL se non convertito (offline/manuale)
  tasso_cambio REAL,                         -- tasso usato per conversione auto, NULL se manuale
  note         TEXT,
  ocr_engine   TEXT,                         -- 'mlkit'|'local_ai'|'claude'|NULL (inserimento manuale)
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_spese_trasferta ON spese(trasferta_id);
CREATE INDEX idx_spese_data ON spese(data);
```


> **Nota multi-valuta:** Il campo `valuta` è pre-compilato dall'OCR in base alla lingua riconosciuta dello scontrino (es. JA → JPY, GB → GBP, DE → EUR); se presenti, hanno priorità i campi **valuta_default** e **lingua_default** della tabella **trasferte**; l'utente può correggerlo nel form. Se online, la conversione EUR può essere recuperata automaticamente via API pubblica (es. `frankfurter.app`, no key richiesta); se offline, il campo resta vuoto e l'utente può compilarlo manualmente in un secondo momento.

**Categorie:** `pranzo` · `cena` · `colazione` · `trasporto` · `taxi` · `hotel` · `parcheggio` · `carburante` · `telefono` · `altro`

### Tabella `foto`

```sql
CREATE TABLE foto (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  spesa_id   INTEGER NOT NULL UNIQUE REFERENCES spese(id),
  file_path  TEXT NOT NULL,                  -- JPG compresso (qualità da settings, default 70%, max 1920px)
  thumb_path TEXT NOT NULL,                  -- thumbnail 300px in thumbnails/
  created_at TEXT NOT NULL
);
```

> **Relazione 1:1 foto↔spesa** Una spesa può esistere senza foto (inserimento manuale). La foto è sempre opzionale. Il vincolo `UNIQUE(spesa_id)` enforza l'1:1.
> I path sono relativi alla directory foto configurata (così restore/cambio directory non rompe i riferimenti).

---

## 🔴 Note implementative — Gap critici

### 1. Backup & Recovery
- **Backup locale:** zip di `nota_spese.db` + cartella foto → salvato in directory scelta dall'utente (share sheet o path configurato). Trigger: manuale da schermata Impostazioni.
- **Backup Google Drive (v1.1):** predisporre l'interfaccia `BackupService` con metodo `uploadToDrive()` stub — implementazione effettiva rimandata a v1.1 con `google_sign_in` + `googleapis`. Il backup locale è sufficiente per v1.0.
- **Restore:** importa zip, sovrascrive DB e cartella foto. Solo da backup locale in v1.0.

### 2. Gestione File Foto
- **Directory:** configurabile dall'utente nella schermata Impostazioni (default: storage interno app). La scelta viene salvata in `SharedPreferences`.
- ⚠️ **Vincolo directory (scoped storage):** su Android 13+ una directory arbitraria esterna implica SAF/`content://` URI (niente path file diretti, gestione permessi persistenti). Per v1.0 limitare la scelta a: storage interno app (`getApplicationDocumentsDirectory()`) o external app-specific (`getExternalFilesDir()`) — entrambe con path reali e senza permessi extra. Directory arbitrarie via SAF → v1.1 se serve.
- **Compressione:** ogni foto viene compressa in JPG (qualità configurabile in Impostazioni, **default 70%**, max 1920px lato lungo) con `flutter_image_compress` prima del salvataggio su disco. L'originale non viene conservato. Il cambio qualità vale solo per le foto nuove (nessuna ricompressione retroattiva).
- **Thumbnail:** generato contestualmente alla compressione (300px), salvato in sottocartella `thumbnails/`.
- **Cancellazione:** alla rimozione di una spesa, tutti i file foto e thumbnail associati vanno eliminati dal filesystem prima di cancellare il record DB. La sequenza è: cancella spesa da interfaccia → cancella file fisici → cancella record `foto` → cancella record `spesa`.

### 🌐 OCR — note specifiche

- L'interfaccia `OcrService` deve essere identica per ML Kit, IA locale e API. I chiamanti non sanno quale motore è attivo.
- Lingue da supportare nel parser: **IT, EN, JA, SR, DE** (+ altre comuni). Per ogni lingua: pattern per data e per importo.
- ⚠️ **Gap cirillico:** ML Kit Text Recognition v2 non supporta il cirillico (serbo in latinica sì). Mitigazione v1.0: scontrini SR in cirillico → motore Claude API; eventuale PaddleOCR-cyrillic in v1.1. Detection/crop: nessun detector custom (YOLO/MobileNet scartati — training custom + licenza AGPL per YOLO), si usa ML Kit Document Scanner → vedi **`docs/catena-detection-ocr.md`**.
- Data: prima tenta dallo scontrino, fallback alla data odierna. Mai bloccare il flusso per data mancante.
- Importo: cerca il valore maggiore + parola chiave totale/total/合計/итого/gesamt nella lingua rilevata.


### 3. Valuta Multipla
- Il paese, quindi la lingua e valuta, puo essere impostata nelle opzioni della singola trasferta, in modo da avere una base per il riconoscimento
- Importo salvato sempre nella **valuta originale** (`importo` + `valuta` ISO 4217).
- **Riconoscimento valuta dallo scontrino:** inferisce la valuta dalla lingua riconosciuta (se non specificata nelle impostazioni della trasferta) (es. JA → JPY, SR → RSD, GB/EN-UK → GBP, CH → CHF, US/EN-US → USD, area euro → EUR). L'utente può correggere nel form di conferma.
- **Conversione EUR — non obbligatoria:**
  - Se **online**: conversione automatica al salvataggio via `frankfurter.app` (API pubblica gratuita, no key). Il campo `importo_eur` viene valorizzato silenziosamente.
  - Se **offline** o se l'utente preferisce: campo `importo_eur` editabile manualmente nel form, lasciabile vuoto.
- I totali della trasferta mostrano la somma nella valuta originale, più eventuale conversione in EUR se disponibile.
- Valute supportate: lista enum nel codice (EUR, JPY, USD, GBP, CHF, RSD, AED, SGD, ecc.) — nessuna API esterna per la lista valute. ⚠️ Non includere HRK: la kuna croata è stata sostituita dall'EUR nel 2023.

### 4. API Key Claude Vision
- ⚠️ **Fatturazione:** l'API NON è inclusa negli abbonamenti Claude Pro/Max (che coprono solo le app claude.ai/Claude Code). Serve un account su platform.claude.com con crediti prepagati pay-as-you-go; l'API key viene da lì. Costo stimato al volume del progetto: ~$0,2-0,35/mese con `claude-haiku-4-5`.
- Inserita dall'utente nella schermata **Impostazioni**.
- Salvata con `flutter_secure_storage` → Android Keystore (mai in SharedPreferences in chiaro).
- Se assente o vuota: il motore Claude Vision API è disabilitato nell'UI, non selezionabile.

### 5. Eliminazione a Cascata
- SQLite non enforza FK di default: attivare `PRAGMA foreign_keys = ON` all'apertura di ogni connessione
- La cancellazione di una trasferta avviene in sequenza esplicita nel repository: foto fisiche → record `foto` → record `spese` → record `trasferta` (tutto in una singola transazione SQLite).
- Non affidarsi al `ON DELETE CASCADE` del DDL senza aver verificato che il PRAGMA sia attivo.

### 6. Migrazione DB
- **Non prevista per v1.0.** In caso di modifica schema, l'utente ripristina da backup (punto 1). Il numero di versione DB viene comunque incrementato in `db_helper.dart` per futura compatibilità.
- La strategia di migrazione formale (con script per versione) è rimandato a v1.1 se il progetto cresce.

### 7. Permessi Android
- Target: **API 33+** (Android 13+). Permessi fotocamera e storage seguono il modello granulare introdotto in API 33.
- Permessi richiesti in `AndroidManifest.xml`: `CAMERA`, `READ_MEDIA_IMAGES` (no `READ_EXTERNAL_STORAGE` su API 33+).
- La richiesta runtime dei permessi va gestita con `permission_handler` o direttamente via `image_picker` (che gestisce autonomamente i permessi camera da API 33).
- Non supportare API < 33 semplifica il codice ed esclude casi limite legacy.

### 8. Currency Picker — UX
- ISO 4217 ha ~170 valute attive: un `DropdownButton` piatto è inutilizzabile su mobile.
- Implementare un **searchable picker**: campo testo filtro + lista scrollabile. Valute più usate in cima (EUR, USD, JPY, GBP, CHF, RSD, AED, SGD).
- Nessun package esterno necessario: componente custom in `shared/widgets/currency_picker.dart`.

### 9. Restore → Reload stato app
- Sequenza restore: valida zip → chiudi connessione DB (`db.close()`) → sovrascrivi `nota_spese.db` e cartella foto → riapri DB → ricarica settings.
- Reload UI senza package esterni: widget radice `RestartWidget` (cambia `Key` del sottoalbero → tutti i controller vengono ricreati e rileggono dal DB). In alternativa v1.0 minima: dialog "Backup ripristinato — riavvia l'app".
- Durante il restore: UI bloccata da progress modale; in caso di errore lo zip NON deve lasciare stato misto → restore su file temporanei, swap solo a estrazione completata.

### 10. Testing — receipt_parser.dart
- Il parser multilingua è il componente più fragile del progetto. Senza fixture di test è impossibile verificare regressioni.
- Creare una suite di **scontrini campione** (file `.txt`) per ogni lingua supportata (IT, EN, JA, SR, DE) e unit test che verificano importo, fornitore e data estratti correttamente.
- l'utente predispone una directory contenente immagini di scontrini campione per i test

### 11. Crescita storage foto
- 90 spese/mese × ~400KB (foto compressa) = ~35MB/mese → ~420MB/anno.
- Aggiungere nella schermata Impostazioni un **indicatore dello spazio usato** dalla cartella foto dell'app. Nota implementativa: `Directory.stat()` NON restituisce la dimensione del contenuto — iterare i file con `Directory.list(recursive: true)` e sommare `FileStat.size` (o `File.length()`).
- Nessuna soglia automatica in v1.0: l'utente gestisce manualmente.


## ✅ Checklist sviluppo

La checklist operativa completa, per fasi con criteri di verifica, è in **`ToDo.md`** (fonte di verità per l'avanzamento). Riepilogo fasi:

| Fase | Contenuto | Dipende da |
|---|---|---|
| 0 | Studio fattibilità OCR IA locale + setup progetto Flutter, lint, struttura cartelle, tema | — |
| 1 | Data layer: schema DB, modelli, repository + unit test | 0 |
| 2 | Shell UI: bottom nav, lista trasferte, CRUD trasferte | 1 |
| 3 | Spese: form manuale, tastiera numerica, categorie, currency picker, totali | 2 |
| 4 | Foto: camera, crop, compressione, thumbnail, viewer, permessi | 3 |
| 5 | OCR: interfaccia OcrService, ML Kit, receipt_parser multilingua + fixture, Claude Vision, IA locale (se fattibile) | 4 |
| 6 | Valuta: conversione EUR frankfurter.app, riconoscimento valuta | 5 |
| 7 | Export: CSV, PDF con foto, share sheet | 3 (foto per PDF: 4) |
| 8 | Impostazioni complete + backup/restore | 5, 6 |
| 9 | Archivio/search, polish, test end-to-end, release build | tutte |

---

## 📊 Effort stimato totale

Stime a sessione di sviluppo assistito (progetto hobby, part-time):

| Fase | Stima | Note |
|---|---|---|
| 0 — Studio IA locale + setup | 1.5 g | studio fattibilità (~1 g) + scaffold + tema |
| 1 — Data layer | 1.5 g | include test repository |
| 2 — Shell + trasferte | 2 g | prima UI navigabile |
| 3 — Spese manuali | 2.5 g | form + tastiera + picker = molta UI custom |
| 4 — Foto | 2 g | pipeline camera→compressione + permessi |
| 5 — OCR + parser | 4-5.5 g | componente più fragile, fixture 5 lingue; +1.5 g se IA locale fattibile |
| 6 — Valuta | 1 g | API semplice, gestione offline |
| 7 — Export | 2 g | PDF con layout è la parte lunga |
| 8 — Settings + backup | 2 g | restore atomico da testare bene |
| 9 — Polish + release | 1.5 g | e2e manuale, icona, build firmata |
| **Totale** | **~20-21.5 g** | ~5-6 settimane part-time |
