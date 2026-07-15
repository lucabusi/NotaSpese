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


> **Future option (v1.1):** aggiungere plugin contrast/brightness quando necessario — il punto di aggancio deve essere  già previsto nel flusso Camera.
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

(da complilare)

## 🏗️ Architettura — Layer
(da complilare)

### Presentation layer

Schermate principali
- **Lista trasferte** — home, badge totale €, ordinamento per data
- **Dettaglio trasferta** — lista spese, totali per categoria, FAB `+`
- **Inserimento spesa** — form + conferma OCR/IA per riconoscimento automatico
- **Export** — PDF (copertina + tabella + foto) e CSV, condivisione via share sheet Android
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
Camera (image_picker)
  └→ Anteprima immediata
       └→ [pulsante "✎ Edit" opzionale]
            └→ image_cropper (crop + rotazione)
                 └→ [future_option v1.1: contrast/brightness]
  └→ Compressione JPG (flutter_image_compress)
       ├→ Qualità target: 85% · dimensione max: 1920px lato lungo
       ├→ Output: file compresso in directory configurata dall'utente
       └→ Thumbnail generato contestualmente (300px) per uso in lista UI
  └→ OCR (motore selezionabile)
       ├→ ML Kit offline    ← default, funziona senza rete
       ├→ Riconoscimento con IA (locale o rete)
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
- Impostazione globale in **Settings** (`ML Kit` di default)
- Override per singolo scatto disponibile nell'UI camera
- Se selezionata l'API ma il dispositivo è offline → fallback automatico a ML Kit
- Supporto per IA locali sul dispositivo
- **API key Claude Vision** — inserita dall'utente nella schermata Impostazioni; salvata con `flutter_secure_storage` (Android Keystore, non SharedPreferences in chiaro)

** UI CRUD di esempio
as example Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/f129b2b3-d819-44f2-ae0c-074c3733be54?file=Trasferte.dc.html

example: Trasferte.dc.html per l'interfaccia UI

- [ ] Bottom nav bar (3 tab: Trasferte attive / Archivio / Impostazioni)
- [ ] Lista trasferte con badge totale € — filtro per `archiviata = 0` / `archiviata = 1`
- [ ] Dettaglio trasferta con lista spese e totali per categoria (in EUR)
- [ ] FAB "+" con scelta: 📷 Scatta scontrino / ✏️ Inserimento manuale
- [ ] Form inserimento/modifica spesa:
  - [ ] Importo originale + `currency_picker.dart` (searchable, pre-compilato da OCR)
  - [ ] Campo importo EUR — opzionale, non obbligatorio; se online si compila automaticamente via `frankfurter.app`, altrimenti editabile manualmente o lasciabile vuoto
  - [ ] Tastiera numerica, categoria chip-select, data auto oggi
  - [ ] Foto allegata: mostra thumbnail se presente, pulsante "Aggiungi foto" se assente
- [ ] Visualizzatore foto scontrino (full screen)
- [ ] Schermata Impostazioni:
  - [ ] Selezione motore OCR default (ML Kit / Claude Vision API)
  - [ ] Inserimento e salvataggio API key Claude Vision (via `flutter_secure_storage`)
  - [ ] Scelta directory salvataggio foto
  - [ ] Indicatore spazio usato dalla cartella foto (`Directory.stat()`)
  - [ ] Trigger backup manuale (esporta zip DB + foto)
- [ ] Gestione permessi Android API 33+ (`CAMERA`, `READ_MEDIA_IMAGES`) a runtime


## 🗄️ Modello Dati

### Tabella `trasferte`


### Tabella `spese`


> **Nota multi-valuta:** Il campo `valuta` è pre-compilato dall'OCR in base alla lingua riconosciuta dello scontrino (es. JA → JPY, GB → GBP, DE → EUR); l'utente può correggerlo nel form. Se online, la conversione EUR può essere recuperata automaticamente via API pubblica (es. `frankfurter.app`, no key richiesta); se offline, il campo resta vuoto e l'utente può compilarlo manualmente in un secondo momento.

**Categorie:** `pranzo` · `cena` · `colazione` · `trasporto` · `taxi` · `hotel` · `parcheggio` · `carburante` · `telefono` · `altro`

### Tabella `foto`

> **Relazione 1:1 foto↔spesa** Una spesa può esistere senza foto (inserimento manuale). La foto è sempre opzionale.

---

## 🔴 Note implementative — Gap critici

### 1. Backup & Recovery
- **Backup locale:** zip di `nota_spese.db` + cartella foto → salvato in directory scelta dall'utente (share sheet o path configurato). Trigger: manuale da schermata Impostazioni.
- **Backup Google Drive (v1.1):** predisporre l'interfaccia `BackupService` con metodo `uploadToDrive()` stub — implementazione effettiva rimandata a v1.1 con `google_sign_in` + `googleapis`. Il backup locale è sufficiente per v1.0.
- **Restore:** importa zip, sovrascrive DB e cartella foto. Solo da backup locale in v1.0.

### 2. Gestione File Foto
- **Directory:** configurabile dall'utente nella schermata Impostazioni (default: storage interno app). La scelta viene salvata in `SharedPreferences`.
- **Compressione:** ogni foto viene compressa in JPG (qualità 70%, max 1920px lato lungo) con `flutter_image_compress` prima del salvataggio su disco. L'originale non viene conservato.
- **Thumbnail:** generato contestualmente alla compressione (300px), salvato in sottocartella `thumbnails/`.
- **Cancellazione:** alla rimozione di una spesa, tutti i file foto e thumbnail associati vanno eliminati dal filesystem prima di cancellare il record DB. La sequenza è: cancella spesa da interfaccia → cancella file fisici → cancella record `foto` → cancella record `spesa`.

### 🌐 OCR — note specifiche

- L'interfaccia `OcrService` deve essere identica per ML Kit, IA locale e API. I chiamanti non sanno quale motore è attivo.
- Lingue da supportare nel parser: **IT, EN, JA, SR, DE** (+ altre comuni). Per ogni lingua: pattern per data e per importo.
- Data: prima tenta dallo scontrino, fallback alla data odierna. Mai bloccare il flusso per data mancante.
- Importo: cerca il valore maggiore + parola chiave totale/total/合計/итого/gesamt nella lingua rilevata.


### 3. Valuta Multipla
- Il paese, quindi la lingua e valuta, puo essere impostata nelle opzioni della singola trasferta, in modo da avere una base per il riconoscimento
- Importo salvato sempre nella **valuta originale** (`importo` + `valuta` ISO 4217).
- **Riconoscimento valuta dallo scontrino:** inferisce la valuta dalla lingua riconosciuta (se non specificata nelle impostazioni della trasferta) (es. JA → JPY, SR → RSD, GB/EN-UK → GBP, CH → CHF, US/EN-US → USD, area euro → EUR). L'utente può correggere nel form di conferma.
- **Conversione EUR — non obbligatoria:**
  - Se **online**: conversione automatica al salvataggio via `frankfurter.app` (API pubblica gratuita, no key). Il campo `importo_eur` viene valorizzato silenziosamente.
  - Se **offline** o se l'utente preferisce: campo `importo_eur` editabile manualmente nel form, lasciabile vuoto.
- I totali della trasferta mostrano la somma nella valuta originiale, piu eventuale conversione in EUR se disponibile.
- Valute supportate: lista enum nel codice (EUR, JPY, USD, GBP, CHF, HRK, RSD, AED, SGD, ecc.) — nessuna API esterna per la lista valute.

### 4. API Key Claude Vision
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
- Implementare un **searchable picker**: campo testo filtro + lista scrollabile. Valute più usate in cima (EUR, USD, JPY, GBP, CHF, HRK, AED, SGD).
- Nessun package esterno necessario: componente custom in `shared/widgets/currency_picker.dart`.

### 9. Restore → Reload stato app
(da complilare)

### 10. Testing — receipt_parser.dart
- Il parser multilingua è il componente più fragile del progetto. Senza fixture di test è impossibile verificare regressioni.
- Creare una suite di **scontrini campione** (file `.txt`) per ogni lingua supportata (IT, EN, JA, SR, DE) e unit test che verificano importo, fornitore e data estratti correttamente.
- l'utente predispone una directory contenente immagini di scontrini campione per i test

### 11. Crescita storage foto
- 90 spese/mese × ~400KB (foto compressa) = ~35MB/mese → ~420MB/anno.
- Aggiungere nella schermata Impostazioni un **indicatore dello spazio usato** dalla cartella foto dell'app (calcolato con `Directory.stat()`).
- Nessuna soglia automatica in v1.0: l'utente gestisce manualmente.


## ✅ Checklist sviluppo
(da complilare)

---

## 📊 Effort stimato totale
(da complilare)
