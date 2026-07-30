# Conversione EUR per tutte le valute + riepilogo per valuta — Design

Data: 2026-07-30 · Stato: approvato (brainstorming con utente)

## Obiettivo

Due requisiti, dalla richiesta utente del 2026-07-30 (registrata in `ToDo.md`
fase 7):

1. **Tutte le valute vanno convertite in EUR e incluse nel totale.** Oggi
   `ExchangeService` interroga solo `frankfurter.app` (tassi BCE, ~30 valute):
   le spese in valute fuori da quel set restano con `importo_eur` NULL e sono
   escluse da ogni totale EUR. Il limite era già annotato in `ToDo.md` fase 6
   ("RSD e AED senza conversione automatica").
2. **Il riepilogo deve rendere chiaro quali spese sono state fatte in quali
   valute.** Oggi l'unica traccia è la nota "esclude N spese non convertite",
   che dice quante spese mancano ma non in che valuta né quanto.

## Evidenza raccolta (2026-07-30, chiamate reali)

| Verifica | Esito |
|---|---|
| Valute dell'enum `Currency` fuori dal set BCE | **10**: RSD, AED, KWD, QAR, SAR, TWD, VND, ALL, BAM, MKD |
| `@fawazahmed0/currency-api` via jsDelivr (no key, storico giornaliero) | copre **tutte e 38** le valute dell'enum |
| Cross-check JPY→EUR del 2026-07-15 | BCE `0,0054` vs fawazahmed0 `0,0053926937` → delta 0,14% |
| Storico fonte secondaria | disponibile dal 2024 (weekend inclusi), **404 sul 2020-01-15** |
| `api.frankfurter.app` | risponde **301 → `api.frankfurter.dev/v1/`** |

Il 301 non è oggi un bug visibile (il pacchetto `http` di Dart segue i redirect
per default), ma costa un round-trip a ogni conversione ed è una dipendenza da
un redirect che il provider può rimuovere. Va corretto contestualmente.

## Decisioni prese (con l'utente)

1. **Catena ibrida, BCE prima.** `frankfurter` resta la fonte primaria per le
   valute che la BCE pubblica; la fonte community copre solo il buco. Motivo:
   i tassi BCE sono quelli citabili in un rimborso spese.
2. **Spese già salvate senza conversione: azione manuale on-demand.** Un
   pulsante "Ricalcola" nel dettaglio trasferta, non un backfill automatico
   all'apertura: niente traffico di rete né scritture DB a sorpresa. Risolve
   anche la nota lasciata aperta in `ToDo.md` dopo BUG-01.
3. **Riepilogo per valuta: n. spese + totale in valuta originale + ≈EUR.**
   Es. `JPY · 13 spese · ¥114.860 · ≈ €661,89`.

### Compromessi accettati esplicitamente

- **Due fonti tassi nello stesso report.** In una trasferta con JPY e AED, il
  primo importo EUR deriva dalla BCE e il secondo dalla fonte community. Non
  viene aggiunta una colonna "fonte" in DB: `spese.tasso_cambio` è già salvato
  per riga, quindi ogni importo resta verificabile a posteriori. Aggiungerla in
  seguito richiederebbe una migrazione di schema.
- **"Tutte convertite" non è una garanzia assoluta.** Offline, o per date
  anteriori al 2024 (la fonte secondaria non ha storico precedente),
  `importo_eur` resta NULL. Ciò che cambia è che **nessuna valuta è più esclusa
  per costruzione**: i fallimenti restano transitori, visibili nel breakdown e
  recuperabili col pulsante Ricalcola.

## Componenti

### 1. `lib/services/currency/exchange_service.dart` — catena a due fonti

La firma pubblica di `convert()` non cambia. Cambia solo `_fetchRate`:

```
convert(amount, from, date)
  ├─ from == 'EUR'            → rate 1.0, nessuna rete            (invariato)
  ├─ tassiOnline == false     → null                              (invariato)
  ├─ cache sessione 'yyyy-MM-dd|CUR'                               (invariato)
  └─ _fetchRate(day, from)
       ├─ from ∉ _ecbUnsupported → _fetchEcbRate(day, from)
       │     ├─ rate trovato        → usa questo
       │     └─ unsupported (404)   → aggiunge from a _ecbUnsupported
       └─ _fetchGlobalRate(day, from)
```

`_fetchEcbRate` restituisce un record Dart 3
`({double? rate, bool unsupported})` per distinguere due esiti che oggi
collassano entrambi su `null`:

- `unsupported: true` — HTTP **404**: la valuta non esiste nel set BCE. Esito
  permanente, il codice valuta entra in `_ecbUnsupported` (`Set<String>`, vita
  di sessione) e le conversioni successive per quella valuta saltano la BCE.
  Prima spesa in AED = 2 richieste, successive = 1.
- `unsupported: false` con `rate: null` — timeout, socket, non-200 diverso da
  404, JSON malformato. Esito **transitorio**: non viene memorizzato nulla,
  al tentativo successivo la BCE viene reinterrogata.

Endpoint:

- BCE: `https://api.frankfurter.dev/v1/$day?from=$from&to=EUR` — dominio nuovo,
  elimina il 301. Risposta invariata: `{"rates":{"EUR":<num>}}`.
- Globale: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$day/v1/currencies/${from.toLowerCase()}.json`
  → si legge `body[from.toLowerCase()]['eur']`. Payload ~7,5 KB compressi (il
  file contiene anche le cripto: nessun endpoint per singola coppia esiste,
  verificato). Nessun caching negativo su questa fonte: un 404 qui può
  significare sia "data non coperta" sia "valuta ignota", entrambi già gestiti
  dal ritorno `null`.

Il contratto "non lancia mai verso i chiamanti" resta invariato: qualunque
fallimento di entrambe le fonti produce `null` e il flusso di inserimento
spesa non viene mai bloccato.

### 2. `lib/data/models/valuta_breakdown.dart` — nuovo tipo di aggregazione

```dart
/// Per-currency slice of a trip: how many expenses, how much in the original
/// currency, how much of that is converted, and how much is still missing.
class ValutaBreakdown {
  const ValutaBreakdown({
    required this.valuta,
    required this.count,
    required this.totale,
    required this.totaleEur,
    required this.countSenzaEur,
  });

  final String valuta;
  final int count;
  final double totale;
  final double totaleEur;
  final int countSenzaEur;
}
```

Nello stesso file, l'**ordinamento accentrato**:

```dart
/// Trip currency first, then descending by original-currency total.
List<ValutaBreakdown> ordinaPerValuta(
    List<ValutaBreakdown> righe, String valutaTrasferta);
```

Questa regola oggi è **duplicata** in due punti con la stessa logica:
`righeValuta` in `lib/ui/shared/currency_rows.dart:4` (su `Map<String, double>`)
e il sort inline in `lib/services/export/trasferta_report.dart:68-73`.

La duplicazione viene **ridotta, non eliminata**: il sort inline del report
sparisce a favore di `ordinaPerValuta`, e anche l'header del dettaglio smette
di usare `righeValuta` perché passa al breakdown. `righeValuta` **resta** in
vita perché la lista trasferte (`trip_card`) continua a lavorare su
`Map<String, double>` — la sua migrazione è dichiarata fuori scope. Le due
funzioni restano quindi coesistenti finché quella migrazione non avviene, con
domini di input diversi (mappa vs lista di breakdown).

Il file del modello sta in `data/models/` (accanto a `Spesa`) e non sotto
`ui/`, così il layer export può importarlo senza dipendere dalla UI.

### 3. `lib/data/repositories/spesa_repository.dart` — una query al posto di tre

```dart
Future<List<ValutaBreakdown>> breakdownPerValuta(int trasfertaId);
```

```sql
SELECT valuta,
       COUNT(*)                                          AS n,
       SUM(importo)                                      AS totale,
       COALESCE(SUM(importo_eur), 0)                     AS totale_eur,
       SUM(CASE WHEN importo_eur IS NULL THEN 1 ELSE 0 END) AS senza_eur
FROM spese WHERE trasferta_id = ? GROUP BY valuta
```

Sostituisce le tre chiamate separate `totaliPerValuta` + `totaleEur` +
`countSenzaEur` sul percorso del dettaglio trasferta. I tre metodi esistenti
**restano** finché la lista trasferte li usa (vedi §Fuori scope).

### 4. `lib/services/currency/conversion_backfill_service.dart` — nuovo

```dart
class BackfillOutcome {
  final int convertite;
  final int fallite;
}

class ConversionBackfillService {
  Future<BackfillOutcome> run(int trasfertaId);
}
```

Carica le spese della trasferta con `importo_eur == null`, per ciascuna chiama
`ExchangeService.convert`, e per quelle riuscite aggiorna `importo_eur` e
`tasso_cambio`. Le fallite restano NULL. Non lancia mai: un errore su una
spesa la conta come fallita e prosegue con le altre. La cache di sessione di
`ExchangeService` collassa le richieste per stessa coppia giorno+valuta, quindi
N spese dello stesso giorno e valuta costano una sola chiamata.

### 5. UI — dettaglio trasferta

- L'header passa da riga singola per valuta (solo importo) a riga completa:
  `JPY · 13 spese · ¥114.860 · ≈ €661,89`. La riga `≈ EUR` per valuta è omessa
  quando la valuta è già EUR (evita `€100 · ≈ €100`) o quando `totaleEur` di
  quella valuta è 0 per mancata conversione.
- Sotto le righe, `TextButton` **"Ricalcola"** visibile solo quando
  `countSenzaEur > 0` complessivo. Durante l'esecuzione mostra un indicatore di
  avanzamento; a fine corsa una SnackBar riporta l'esito:
  - tutte riuscite → `Convertite N spese`
  - parziale → `Convertite N spese su M`
  - nessuna → `Nessun tasso disponibile: controlla la connessione`
- La nota generica `esclude N spese senza conversione` sparisce dal riepilogo
  per valuta: l'informazione è ora per riga. Resta invece nell'header della
  lista trasferte, dove il breakdown non è disponibile.

### 6. Export — copertina PDF e sintesi CSV

`TrasfertaReport` guadagna `List<ValutaBreakdown> breakdown` (costruito dalle
stesse spese, ordinato con `ordinaPerValuta`), mantenendo `totaliPerValuta`,
`totaleEur` e `countSenzaEur` per i consumatori esistenti.

- **PDF**, blocco TOTALI della copertina: una riga per valuta nel formato
  concordato. `coverEurNote` si semplifica a una sola regola: restituisce
  `≈ €X` se `totaleEur > 0`, altrimenti **`null`**. Sparisce sia la coda
  "(esclude N spese non convertite)" sia il ramo che oggi restituisce la sola
  nota di esclusione quando `totaleEur == 0`: entrambe le informazioni sono
  ora esplicite nelle righe per valuta, e con `totaleEur == 0` una riga
  "≈ €0,00" sarebbe fuorviante. Il commento dottrinale attuale della funzione
  (che motiva il gating su `countSenzaEur`) va riscritto di conseguenza.
- **CSV**, riga di sintesi: una colonna per valuta con conteggio e totale,
  stessa sostanza del PDF.

Il **layout grafico** del PDF (palette blu, card, barre — mockup C approvato
il 2026-07-30) è una modifica separata e successiva: questa spec tocca solo i
*dati* mostrati in copertina, non il loro stile.

## Nessuna modifica di schema

`spese.importo_eur` e `spese.tasso_cambio` esistono già dalla fase 1.
`dbVersion` resta **1**, nessuna migrazione, nessun rischio sulle installazioni
esistenti.

## Test

Tutti eseguibili su host, nessun device richiesto.

**`test/exchange_service_test.dart`** (estensione)
- il percorso BCE chiama `api.frankfurter.dev` con path `/v1/$day`
- BCE 404 → fallback alla fonte globale, conversione corretta dalla shape
  annidata `{"aed":{"eur":0.23}}`
- BCE timeout → fallback alla fonte globale
- entrambe le fonti KO → `null`, nessuna eccezione
- seconda conversione della stessa valuta 404-ata → **una sola** richiesta
  (BCE saltata)
- BCE in timeout → la valuta **non** entra in `_ecbUnsupported`: la richiesta
  successiva reinterroga la BCE
- 404 dalla fonte globale (data pre-2024) → `null`
- EUR continua a non toccare la rete

**`test/repositories_test.dart`** (estensione)
- `breakdownPerValuta`: conteggi, somme per valuta, `countSenzaEur` per valuta,
  `totaleEur` a 0 quando nessuna spesa della valuta è convertita
- ordinamento: valuta della trasferta prima, poi decrescente per totale

**`test/conversion_backfill_test.dart`** (nuovo)
- converte solo le righe con `importo_eur` NULL, non tocca le altre
- scrive sia `importo_eur` sia `tasso_cambio`
- conversione fallita → riga lasciata NULL, contata in `fallite`
- outcome con i conteggi corretti; nessuna eccezione propagata

**`test/export/`** (estensione)
- `TrasfertaReport.breakdown` con valute miste e ordinamento
- copertina PDF: una riga per valuta; `coverEurNote` senza la parte "esclude"
- sintesi CSV con i conteggi per valuta

**Widget** (`trasferta_detail_screen_test.dart`)
- righe per valuta con conteggio e ≈EUR
- riga `≈ EUR` omessa per la valuta EUR
- "Ricalcola" assente con `countSenzaEur == 0`, presente altrimenti
- tap su "Ricalcola" → SnackBar con l'esito

## Fuori scope (dichiarato)

- **Lista trasferte / `trip_card`**: continuano a usare `totaliPerValuta` +
  `totaleEur` + `countSenzaEur`. Migrarli a `breakdownPerValuta` ridurrebbe le
  query da 3 a 1 per trasferta, ma è un'ottimizzazione indipendente dalla
  richiesta ed espande il diff. Candidato a follow-up.
- **Colonna "fonte tasso" in DB**: vedi Compromessi.
- **Totali per categoria**: la regola attuale (valuta originale se la trasferta
  ne ha una sola, altrimenti EUR escludendo le non convertite) resta invariata.
  Con tutte le valute convertibili il caso di esclusione diventa raro, e la
  nota "N spese senza conversione EUR" già presente sotto le categorie copre la
  visibilità.
- **Nuovo layout grafico del PDF** (mockup C blu): modifica successiva.

## Versione

`0.11.0+16` → `0.12.0+17` (`pubspec.yaml` + `lib/version.dart`).
