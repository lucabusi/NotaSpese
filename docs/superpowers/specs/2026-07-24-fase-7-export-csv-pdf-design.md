# Fase 7 — Export CSV / PDF — Design

Data: 2026-07-24
Stato: approvato (brainstorming), pronto per il piano di implementazione.

## Obiettivo

Esportare le spese di una singola trasferta in due formati, condivisibili via
share sheet Android:

- **CSV**: dati flat (una riga per spesa) + riga totale, importabile in Excel/Calc IT.
- **PDF**: copertina con i totali + tabella spese + pagine con le foto degli scontrini.

L'export non è una schermata dedicata: due voci nel menu del dettaglio trasferta.

## Decisioni prese (brainstorming 2026-07-24)

1. **PDF foto**: copertina → tabella → pagine **orizzontali**, **2 scontrini per
   pagina** (foto grande + didascalia: data · fornitore · importo · categoria),
   ordine come la tabella. Spese senza foto: saltate.
2. **CSV**: colonne complete + riga TOTALE; separatore `;`; decimale con virgola;
   UTF-8 con BOM.
3. **Copertina PDF**: totali per valuta originale + totale EUR (esclude N spese non
   convertite) + breakdown per categoria — stessa logica delle schermate app.
4. **Menu**: 2 voci separate "Esporta PDF" / "Esporta CSV", ognuna → share sheet.
5. **Architettura**: report model condiviso puro Dart + renderer sottili (approccio A).
6. **Font PDF**: Noto Sans (latino + €) con fallback Noto Sans JP (nomi fornitore
   giapponesi), embeddati come asset.

## Architettura

Approccio A — un modello di report puro Dart, costruito dai repository, consumato da
due renderer indipendenti. Nessun accesso a filesystem/DB nei renderer; i renderer
ricevono già i dati calcolati.

```
services/export/
  trasferta_report.dart      # modello + builder puro (TrasfertaReport.build)
  csv_export_service.dart    # TrasfertaReport -> String CSV
  pdf_export_service.dart    # TrasfertaReport + risolutore-foto -> Uint8List PDF
```

Dipendenze nuove: `csv`, `pdf`. **`printing` non necessario** (condivisione via
`share_plus`, già dipendenza). Font come asset in `assets/fonts/`.

### Confini

- `TrasfertaReport` non conosce CSV né PDF: solo aggregazione e ordinamento. Testabile
  su host senza device.
- `CsvExportService` non conosce il PDF e viceversa.
- Il PDF riceve un risolutore `int spesaId -> String? pathAssolutoFoto` iniettato dal
  controller (che già espone `fotoBySpesa` + `absolutePhotoPath`); il service non
  legge il DB.

## TrasfertaReport (modello + builder)

`TrasfertaReport.build(Trasferta trasferta, List<Spesa> spese)` — funzione pura.

Campi del modello:

- `trasferta`: riferimento (nome, luogo, dataInizio, dataFine, valutaDefault).
- `righe`: `List<ReportRow>` — le spese ordinate per `data` ascendente, a parità di
  data per `createdAt`. Ogni riga: data, categoria, fornitore, importo, valuta,
  importoEur, tassoCambio, note.
- `totaliPerValuta`: `Map<String, double>` — somma `importo` per valuta. Ordine:
  valuta della trasferta prima, poi per importo decrescente (stesso ordine di
  `currency_rows` in app).
- `totaleEur`: somma degli `importoEur` non null.
- `countSenzaEur`: numero di spese con `importoEur == null`.
- `totaliPerCategoria`: totale per categoria. Se la trasferta ha **una sola valuta**
  fra le spese → totali in quella valuta; altrimenti → in EUR, escludendo le spese non
  convertite (stessa regola dell'app dopo BUG-03).

Il builder non fa I/O: riceve la lista spese già caricata dal `SpesaRepository`.

## CSV

- Encoding: **UTF-8 con BOM** (`﻿` iniziale) così Excel-IT mostra accenti ed €.
- Separatore campo: `;`. Fine riga: `\r\n`.
- Escaping: delegato al package `csv` (`ListToCsvConverter` con `fieldDelimiter: ';'`);
  i campi con `;`, `"` o newline (es. note) vengono quotati.
- Numeri: formattati come **testo** con virgola decimale (es. `19,84`) — non lasciati
  al package, che userebbe il punto. Nessun separatore delle migliaia.
- Date: `dd/MM/yyyy`.

Intestazione:

```
Data;Categoria;Fornitore;Importo;Valuta;Importo EUR;Tasso;Note
```

Corpo: una riga per spesa (ordine del report). Campi null → stringa vuota
(fornitore, importo EUR, tasso, note).

Coda: una riga vuota, poi la riga totale:

```
TOTALE EUR;;;;;<totaleEur>;;esclude N spese non convertite
```

La nota finale è omessa quando `countSenzaEur == 0` (ultima cella vuota).

## PDF

Font: `Noto Sans` (Regular/Bold) come base, `Noto Sans JP` (Regular) come fallback,
così i nomi fornitore giapponesi vengono renderizzati. Il fallback è configurato a
livello di `ThemeData` del documento `pdf`.

### Pagina 1 — Copertina (verticale, A4)

- Titolo: nome trasferta.
- Sottotitolo: luogo · periodo (`dataInizio – dataFine`, "in corso" se dataFine null)
  · numero spese.
- **TOTALI**: una riga per valuta originale (`JPY 42.300`), poi `≈ EUR 262,26`
  con "(esclude N spese non convertite)" se `countSenzaEur > 0`.
- **PER CATEGORIA**: categoria (icona opzionale + label) con il relativo totale, nella
  valuta scelta dalla regola sopra.

### Pagine tabella (verticale, A4)

Colonne: `Data | Categoria | Fornitore | Importo | Valuta | ≈ EUR`.

- Header di tabella ripetuto a ogni pagina (`pw.Table` con page break automatico o
  `MultiPage`).
- `≈ EUR` vuoto se la spesa non ha conversione.
- Ultima riga: totale EUR (allineato con la copertina).

### Pagine foto (orizzontale, A4 landscape)

- 2 scontrini per pagina, impaginati in due metà (sinistra/destra o alto/basso a
  seconda della resa; scelta in implementazione, priorità leggibilità foto).
- Ogni blocco: la foto scalata per riempire la metà pagina mantenendo le proporzioni
  (`pw.Image` da `MemoryImage` del jpg salvato) + didascalia sotto:
  `data · fornitore · importo valuta · categoria`.
- Ordine identico alla tabella. Le spese **senza foto** non generano blocco.
- Il jpg è quello salvato/compresso dall'app; il risolutore foto è passato dal
  controller.

## UI / Consegna

- Due voci nel menu (overflow) dell'appbar del dettaglio trasferta:
  "Esporta PDF" e "Esporta CSV". Disponibili sia per trasferte attive sia archiviate.
- Al tap: caricamento spese + foto dai repository → `TrasfertaReport.build` →
  generazione byte (CSV string / PDF `Uint8List`) → scrittura file temporaneo →
  `Share.shareXFiles([XFile(path)])`.
- Nome file: `NotaSpese_<nomeSlug>_<yyyy-MM>.pdf` / `.csv`, dove `nomeSlug` è il nome
  trasferta ripulito (spazi → `_`, caratteri non sicuri rimossi) e `yyyy-MM` deriva da
  `dataInizio`.
- Indicatore di progresso durante la generazione (il PDF con foto può richiedere
  qualche secondo). Errori → SnackBar, mai crash. Trasferta senza spese → messaggio
  ("nessuna spesa da esportare"), niente file.

## Gestione errori

- Foto mancante/illeggibile a runtime: la spesa viene saltata nelle pagine foto
  (best-effort), il resto del PDF si genera comunque.
- Fallimento scrittura file temporaneo o share: SnackBar di errore, nessun crash.
- Generazione avvolta in modo che un'eccezione non lasci l'indicatore di progresso
  appeso.

## Test

- **Unit `TrasfertaReport.build`**: totali per valuta (ordine incluso), `totaleEur`,
  `countSenzaEur`, `totaliPerCategoria` (mono-valuta vs multi-valuta), ordinamento
  righe (data poi createdAt).
- **Unit CSV**: intestazione, formattazione data/decimali (virgola), campi null vuoti,
  escaping di `;` nelle note, BOM iniziale, riga totale (con e senza nota "esclude N").
- **PDF smoke**: `pdf_export_service` produce byte non vuoti per un report (a) con foto,
  (b) senza foto, (c) con fornitore in giapponese — asserendo solo assenza di eccezioni
  e output non vuoto (il rendering non è verificato su host).
- **Widget**: le due voci di menu esistono nel dettaglio; il tap costruisce il file e
  invoca lo share (share fake/iniettato), senza device.

## Fuori scope (v1.0)

- Export multi-trasferta o dell'intero archivio (solo singola trasferta).
- Anteprima di stampa nativa (`printing`).
- Personalizzazione colonne/layout da parte dell'utente.
- Export di formati aggiuntivi (xlsx, json).

## Impatti

- `pubspec.yaml`: aggiunte `csv`, `pdf`; asset font Noto (Sans + Sans JP).
- Bump versione (`pubspec.yaml` + `lib/version.dart`).
- `services/export/` nuova, come già previsto in `Specifiche.md`.
- Nessuna modifica allo schema DB.
