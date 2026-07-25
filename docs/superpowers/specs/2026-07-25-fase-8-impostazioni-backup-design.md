# Fase 8 — Impostazioni + Backup/Restore — Design

Data: 2026-07-25
Stato: approvato (brainstorming), pronto per il piano di implementazione.

## Obiettivo

Sostituire `ImpostazioniMinimal` (nato fase 5) con una schermata Impostazioni
completa, ed aggiungere backup/restore locale (zip DB + foto).

## Decisioni prese (brainstorming 2026-07-25)

1. **Gestione modello IA locale esclusa dallo scope**: nessun motore
   `LocalAiOcrService` esiste (gate benchmark fase 5 non superato, vedi
   `ToDo.md` fase 5) → nessuna UI di download/stato/eliminazione modello in
   questa fase. Resta rimandata a quando il gate sarà superato.
2. **`ImpostazioniMinimal` sostituita**: nuova `ImpostazioniScreen` in
   `lib/ui/impostazioni/`, riusa la logica esistente (stessi metodi
   `SettingsService`/`ApiKeyStore`); la vecchia classe viene rimossa da
   `home_shell.dart`.
3. **Migrazione directory foto**: al cambio directory, dialog con scelta
   esplicita dell'utente tra "Migra ora" (sposta i file fisici + aggiorna i
   path in DB) e "Lascia dove sono" (vale solo per le foto nuove).
4. **Reload post-restore**: dialog "Backup ripristinato — riavvia l'app"
   (niente `RestartWidget` — meno codice, meno rischio su un flusso mai
   testato su emulatore).
5. **Formato backup**: zip unico self-contained (`nota_spese.db` + cartella
   foto), niente manifest esterno; il restore valida lo schema del DB
   estratto (tabelle attese) prima di sovrascrivere.

## Architettura

```
services/settings/settings_service.dart   # esteso: nessun campo nuovo, resta come oggi
services/backup/backup_service.dart       # nuovo: createBackup / restoreBackup / uploadToDrive (stub)
services/photo/photo_dir_migration.dart   # nuovo: sposta file + aggiorna path DB
ui/impostazioni/impostazioni_screen.dart  # nuovo: sostituisce ImpostazioniMinimal
```

`BackupService` e `photo_dir_migration` non conoscono la UI: ricevono
percorsi/istanze repository e restituiscono risultati (successo/errore),
niente `SnackBar`/dialog al loro interno — quelli restano nello screen.

## `ImpostazioniScreen`

Sezioni, in ordine:

1. **OCR**: selettore motore default (ML Kit/Claude, `SegmentedButton`
   invariato) + campo API key Claude Vision mascherato — logica identica a
   `ImpostazioniMinimal` oggi (`ApiKeyStore`, `SettingsService.ocrEngineDefault`).
2. **Foto**: slider qualità JPG (50–90, default 70, label "vale per le nuove
   foto"); selettore directory (interna/esterna) con dialog di migrazione al
   cambio; indicatore spazio usato dalla cartella foto corrente (MB, calcolo
   on-demand con pulsante refresh).
3. **Cambio**: toggle "Tassi di cambio online" — invariato.
4. **Backup**: pulsante "Backup ora" (progress + share sheet/`file_picker`
   per la destinazione) + pulsante "Ripristina da backup" (`file_picker` zip
   → conferma esplicita "sovrascrive i dati attuali" → dialog riavvia).
5. **Info**: versione app (da `lib/version.dart`).

## Migrazione directory foto

`PhotoDirMigrationService.migrate(from, to)`:

1. `Directory.list(recursive: true)` sulla vecchia dir.
2. Copia ogni file (struttura relativa invariata, incl. `thumbnails/`) nella
   nuova dir.
3. Se tutte le copie riescono: update batch dei path in DB (stessa
   transazione/repository esistente), poi cancella i file vecchi.
4. Se una copia fallisce a metà: abort, cancella i file già copiati nella
   nuova dir, nessun path DB toccato, nessun file vecchio cancellato —
   l'utente resta nello stato precedente e vede un errore.

"Lascia dove sono": nessuna chiamata al servizio, solo
`SettingsService.setPhotoDirKind` — le foto esistenti mantengono i path
assoluti già salvati (continuano a funzionare), solo le foto nuove vanno
nella nuova directory.

## Indicatore spazio usato

`Directory.list(recursive: true)` sulla cartella foto corrente, somma
`FileStat.size`/`File.length()` di tutti i file (foto + thumbnail), mostrato
in MB con 1 decimale. Calcolo eseguito al primo load della sezione e su
richiesta (pulsante refresh), non in polling continuo.

## `BackupService`

```
Future<File> createBackup()               // zip -> file temporaneo, path restituito al chiamante
Future<RestoreResult> restoreBackup(File zip)
Future<void> uploadToDrive()               // stub v1.1, throws UnimplementedError
```

- **`createBackup`**: zip (`archive` package) di `nota_spese.db` (dal path di
  `db_helper.dart`) + intera cartella foto corrente → file temporaneo
  `nota_spese_backup_<yyyyMMdd_HHmmss>.zip`. Il chiamante (screen) lo passa a
  share sheet o lo salva via `file_picker`.
- **`restoreBackup`**:
  1. Estrae lo zip in una directory temporanea.
  2. Apre il DB estratto in sola lettura, verifica presenza delle tabelle
     attese (`trasferte`, `spese`, `foto`) — se mancano o l'apertura fallisce:
     ritorna errore, **nessuna modifica** ai dati correnti.
  3. Se valido: chiude la connessione DB corrente, swap atomico via rename
     (dir/file correnti → `.bak`, temp → posizione finale) sia per il DB sia
     per la cartella foto; cancella `.bak` solo a swap riuscito. Se il rename
     fallisce a metà, ripristina da `.bak` (best-effort) e ritorna errore.
  4. Il chiamante mostra il dialog "Backup ripristinato — riavvia l'app" solo
     a swap riuscito.
- **`uploadToDrive`**: firma presente nell'interfaccia `BackupService` per
  v1.1, corpo non implementato (`UnimplementedError`), mai chiamato dalla UI.

## DB version

Bump della costante versione DB in `db_helper.dart` (nessuna migrazione
formale — v1.0 non la richiede, vedi `Specifiche.md`). Se lo schema estratto
da un vecchio backup non corrisponde, l'utente ripristina da un backup più
recente (nessuna migrazione automatica in v1.0).

## Gestione errori

- Backup: fallimento scrittura zip/spazio insufficiente → SnackBar errore,
  nessun file parziale lasciato (cleanup su eccezione).
- Restore: DB non valido, zip corrotto, spazio insufficiente per
  l'estrazione → SnackBar/dialog errore esplicito, dati correnti intatti
  (mai un abort a metà swap che lasci l'app in stato inconsistente — da qui
  il pattern `.bak` + rollback).
- Migrazione directory: vedi sopra, abort pulito senza foto orfane né path
  rotti.

## Test

- **Unit `BackupService`**: createBackup produce uno zip con DB+foto attesi
  (tmp dir reale, no device); restoreBackup con zip valido (swap riuscito,
  vecchi file rimossi), zip con DB invalido (errore, dati correnti intatti),
  zip corrotto (errore gestito, no crash).
- **Unit `PhotoDirMigrationService`**: migrazione completa riuscita (file +
  path DB aggiornati), fallimento a metà (rollback, nessun path toccato).
- **Widget `ImpostazioniScreen`**: tutte le sezioni renderizzate; slider
  qualità JPG persiste; dialog migrazione (entrambe le scelte) con service
  mockato; flusso backup/restore con `BackupService` fake (successo ed
  errore); rimozione API key.
- Verifica "ciclo completo su emulatore" del `ToDo.md` → **SKIP esplicito**
  (ambiente Android incompleto per emulatore, gotcha `CLAUDE.md`),
  compensato dai test sopra; verifica reale rimandata a un collaudo su
  device fisico (stile fase 6b).

## Fuori scope (v1.0)

- Gestione modello IA locale (download/stato/eliminazione) — vedi decisione 1.
- Backup automatico/Google Drive (`uploadToDrive()` resta stub).
- Migrazione DB formale multi-versione.
- Directory foto arbitraria via SAF (`content://`) — resta limitata a
  interna/esterna app-specific.

## Impatti

- `pubspec.yaml`: aggiunta `archive` (zip), `file_picker` (già previsto in
  `Specifiche.md` per fase 8).
- Bump versione (`pubspec.yaml` + `lib/version.dart`).
- `lib/services/backup/`, `lib/ui/impostazioni/` popolate (erano placeholder
  `.gitkeep`).
- `home_shell.dart`: rimozione `ImpostazioniMinimal`, uso di
  `ImpostazioniScreen`.
- Bump costante versione DB in `db_helper.dart` (nessuna migrazione).
