# Prima Nota in Trasferta — ToDo & Setup

## Stack scelto
- **Framework:** Flutter (Dart)
- **DB:** SQLite locale (`sqflite`)
- **State management:** `ChangeNotifier` + `ListenableBuilder` (built-in Flutter, no Riverpod)
- **OS sviluppo:** Windows + VS Code
- **Target:** Android
- **Contesto d'uso:** single-user, offline-first, ~1-2 trasferte/mese, 60-90 spese/mese

---

## ⚙️ Setup Ambiente

### 1. Installa Java (JDK 17)
- Scarica **Adoptium Temurin 17**: https://adoptium.net
- Verifica: `java -version`

### 2. Installa Android Studio
> Serve solo per SDK Android ed emulatore — si continua a codare in VS Code.
- Scarica: https://developer.android.com/studio
- Durante l'installazione seleziona: ✅ Android SDK ✅ Android Virtual Device
- Al primo avvio completa il wizard (scarica SDK 34+)

### 3. Installa Flutter SDK
- Scarica: https://docs.flutter.dev/get-started/install/windows
- Estrai in `C:\flutter` (evita percorsi con spazi)
- Aggiungi `C:\flutter\bin` al **PATH** di sistema
- Verifica: `flutter doctor`

### 4. Configura VS Code
Installa le estensioni:
- **Flutter** (by Dart Code) — include anche Dart
- **Dart** (by Dart Code)
- **Error Lens** — consigliata, mostra errori inline

### 5. Configura Android Studio (una tantum)
In Android Studio → Settings:
```
Appearance & Behavior → System Settings → Android SDK
→ SDK Tools → spunta: Android SDK Command-line Tools
```
Poi accetta le licenze Android:
```bash
flutter doctor --android-licenses
```

### 6. Crea emulatore Android
In Android Studio → Device Manager → Create Virtual Device:
- Scegli **Pixel 7**
- System image: **API 34 (Android 14)**

### 7. Verifica finale
```bash
flutter doctor
```
Deve mostrare tutto ✅ (Xcode mancante è normale su Windows).

---

## 🚀 Crea il progetto

```bash
flutter create prima_nota --org com.tuonome
cd prima_nota
code .
```

---

## 📦 Dipendenze (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Database
  sqflite: ^2.3.3
  path_provider: ^2.1.3
  path: ^1.9.0

  # Camera e immagini
  image_picker: ^1.1.2
  image_cropper: ^5.0.1        # crop + rotazione (sostituisce image_editor_plus)

  # OCR offline
  google_mlkit_text_recognition: ^0.13.0

  # Export
  pdf: ^3.11.1
  printing: ^5.13.1
  csv: ^6.0.0

  # UI utilità
  intl: ^0.19.0

  # HTTP (per OCR via API quando online)
  http: ^1.2.1
```

> **Rimosso:** `flutter_riverpod` — state management gestito con `ChangeNotifier` built-in.
> **Rimosso:** `image_editor_plus` — sostituito da `image_cropper` (più stabile su Android 13+).
> **Future option (v1.1):** aggiungere plugin contrast/brightness quando necessario — il punto di aggancio è già previsto nel flusso Camera.

Dopo aver modificato `pubspec.yaml`:
```bash
flutter pub get
```

---

## 📁 Struttura progetto

```
lib/
├── main.dart
├── app.dart                       # MaterialApp, theme, router
│
├── data/
│   ├── database/
│   │   ├── db_helper.dart         # init SQLite, migrations, singleton
│   │   └── schema.dart            # CREATE TABLE statements
│   ├── models/
│   │   ├── trasferta.dart
│   │   ├── spesa.dart
│   │   └── foto.dart
│   └── repositories/
│       ├── trasferte_repository.dart
│       ├── spese_repository.dart
│       └── foto_repository.dart
│
├── features/
│   ├── trasferte/                 # lista e dettaglio trasferte
│   ├── spese/                     # form inserimento/modifica spesa
│   ├── camera/                    # acquisizione + edit opzionale (image_cropper)
│   ├── ocr/                       # ML Kit offline + Claude Vision API (selezionabili)
│   │   ├── ocr_service.dart       # interfaccia comune ai due motori
│   │   ├── mlkit_ocr.dart         # implementazione ML Kit
│   │   ├── api_ocr.dart           # implementazione Claude Vision
│   │   └── receipt_parser.dart    # parse multilingua: data, importo, fornitore
│   └── export/                    # CSV e PDF
│
└── shared/
    ├── widgets/                   # componenti riutilizzabili
    ├── notifiers/                 # ChangeNotifier per trasferte e spese
    └── theme.dart
```

---

## 🏗️ Architettura — Layer

### Presentation layer
Flutter widgets + `setState` / `ListenableBuilder`. Nessuna dipendenza esterna per lo state management.

Schermate principali (bottom nav bar a 3 tab):
- **Lista trasferte** — home, badge totale €, ordinamento per data
- **Dettaglio trasferta** — lista spese, totali per categoria, FAB `+`
- **Inserimento spesa** — form + conferma OCR
- **Export** — PDF (copertina + tabella + foto) e CSV, condivisione via share sheet Android
- **Archivio / search** — trasferte chiuse, filtro per anno/mese

### Feature layer
Logica di business con `ChangeNotifier` + `ListenableBuilder`:
- **Camera & OCR** — flusso scontrino (vedi sotto)
- **Trasferte CRUD** — crea / modifica / archivia / elimina
- **Spese CRUD** — inserimento / edit / filtri / totali live
- **Export** — generazione PDF con foto allegate e CSV flat

### Data layer
Repository pattern sopra `sqflite` e filesystem locale:
- `TrasfertaRepository` — CRUD + query aggregate
- `SpesaRepository` — CRUD + filtri + totali
- `FotoRepository` — gestione path file + OCR raw
- `DBHelper` — singleton, init, migrations
- `FileStorage` — foto originali + thumbnails

---

## 🎥 Flusso critico — acquisizione scontrino

```
Camera (image_picker)
  └→ Anteprima immediata
       └→ [pulsante "✎ Edit" opzionale]
            └→ image_cropper (crop + rotazione)
                 └→ [future_option v1.1: contrast/brightness]
  └→ OCR (motore selezionabile)
       ├→ ML Kit offline    ← default, funziona senza rete
       └→ Claude Vision API ← opzionale, richiede rete, più preciso
  └→ Parse multilingua (receipt_parser.dart)
       ├→ Lingue supportate: IT · EN · JA · SR · DE + altre comuni
       ├→ Campi estratti: importo, fornitore, data
       └→ Data: legge dallo scontrino → fallback data odierna
  └→ Form di conferma
       └→ campi pre-compilati, utente corregge e salva
```

### Regole parse — data
1. Lettura dallo scontrino (regex + euristiche per-lingua)
2. Fallback automatico → data odierna
3. L'utente può sempre sovrascrivere nel form di conferma

### OCR — selezione motore
- Impostazione globale in **Settings** (`ML Kit` di default)
- Override per singolo scatto disponibile nell'UI camera
- Se selezionata l'API ma il dispositivo è offline → fallback automatico a ML Kit

---

## 🗄️ Modello Dati

### Tabella `trasferte`
| Campo | Tipo | Note |
|---|---|---|
| `id` | INTEGER PK | autoincrement |
| `titolo` | TEXT | es. "Milano — Convegno Q2" |
| `destinazione` | TEXT | città/luogo |
| `data_inizio` | TEXT | `YYYY-MM-DD` |
| `data_fine` | TEXT | `YYYY-MM-DD` |
| `note` | TEXT | opzionale |
| `created_at` | TEXT | timestamp |
| `updated_at` | TEXT | timestamp |

### Tabella `spese`
| Campo | Tipo | Note |
|---|---|---|
| `id` | INTEGER PK | autoincrement |
| `trasferta_id` | INTEGER FK | → `trasferte.id` |
| `data` | TEXT | `YYYY-MM-DD` |
| `importo` | REAL | es. `12.50` |
| `valuta` | TEXT | default `EUR` |
| `categoria` | TEXT | enum (vedi sotto) |
| `descrizione` | TEXT | opzionale |
| `fornitore` | TEXT | da OCR o manuale |
| `metodo_pagamento` | TEXT | `contanti` / `carta` / `altro` |
| `rimborsabile` | INTEGER | boolean `0/1`, default `1` |
| `stato` | TEXT | `bozza` / `confermata` |
| `created_at` | TEXT | timestamp |
| `updated_at` | TEXT | timestamp |

**Categorie:** `pranzo` · `cena` · `colazione` · `trasporto` · `taxi` · `hotel` · `parcheggio` · `carburante` · `telefono` · `altro`

### Tabella `foto`
| Campo | Tipo | Note |
|---|---|---|
| `id` | INTEGER PK | autoincrement |
| `spesa_id` | INTEGER FK | → `spese.id` |
| `path` | TEXT | percorso file locale |
| `thumbnail_path` | TEXT | versione ridotta per UI |
| `ocr_raw` | TEXT | testo grezzo OCR |
| `ocr_source` | TEXT | `mlkit` / `api` / `manuale` |
| `created_at` | TEXT | timestamp |

---

## ✅ Checklist sviluppo

### Fase 1 — Setup & DB (3-4 giorni)
- [ ] Installare Java, Android Studio, Flutter SDK
- [ ] Configurare VS Code con estensioni Flutter/Dart
- [ ] Creare progetto Flutter
- [ ] Aggiungere dipendenze in `pubspec.yaml`
- [ ] Implementare `db_helper.dart` (singleton, init, migrations)
- [ ] Implementare i 3 model class (`Trasferta`, `Spesa`, `Foto`)
- [ ] Implementare i 3 repository (CRUD + query)
- [ ] Implementare `ChangeNotifier` per trasferte e spese

### Fase 2 — Camera & Editing (2-3 giorni)
- [ ] Acquisizione foto con `image_picker` (camera + galleria)
- [ ] Anteprima immediata post-scatto con pulsante "✎ Edit"
- [ ] Crop e rotazione con `image_cropper` (opzionale, non bloccante)
- [ ] *(future v1.1)* Regolazione luminosità/contrasto — punto di aggancio da prevedere

### Fase 3 — OCR & Parse (4-6 giorni)
- [ ] Interfaccia `OcrService` comune ai due motori
- [ ] OCR offline con ML Kit (`mlkit_ocr.dart`)
- [ ] OCR via API Claude Vision (`api_ocr.dart`) con fallback offline automatico
- [ ] Selezione motore in Settings + override per singolo scatto
- [ ] `receipt_parser.dart` — parse multilingua (IT, EN, JA, SR, DE, altre)
- [ ] Parse campi: importo, fornitore, data (con fallback data odierna)
- [ ] Form di conferma/correzione dati OCR

### Fase 4 — UI CRUD (4-6 giorni)
- [ ] Bottom nav bar (3 tab: Trasferte attive / Archivio / Impostazioni)
- [ ] Lista trasferte con badge totale €
- [ ] Dettaglio trasferta con lista spese e totali per categoria
- [ ] Form inserimento/modifica spesa (importo con tastiera numerica, categoria chip-select, data auto oggi)
- [ ] Visualizzatore foto scontrino (full screen)
- [ ] Schermata Impostazioni (selezione motore OCR default, altre preferenze)

### Fase 5 — Export (3-5 giorni)
- [ ] Export CSV (riga per spesa)
- [ ] Export PDF: copertina + tabella spese + foto allegate
- [ ] Definire template PDF
- [ ] Condivisione via share sheet Android

### Fase 6 — Rifinitura (2-3 giorni)
- [ ] UI/UX polish
- [ ] Gestione errori (offline, OCR fallito, DB corrotto)
- [ ] Testing su dispositivo fisico
- [ ] Verifica lingue OCR (IT, EN, JA, SR, DE)

---

## 📊 Effort stimato totale
**15-23 giorni lavorativi** (sviluppatore singolo, part-time)

| Fase | Giorni | Rischio |
|---|---|---|
| 1 — Setup & DB | 3-4 | basso |
| 2 — Camera & Editing | 2-3 | basso |
| 3 — OCR & Parse multilingua | 4-6 | **alto** — parsing fragile, lingue diverse |
| 4 — UI CRUD | 4-6 | medio |
| 5 — Export | 3-5 | medio — PDF con foto |
| 6 — Rifinitura | 2-3 | basso |
