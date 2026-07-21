# Importo primario nella valuta originale — Design

Data: 2026-07-21 · Stato: approvato (brainstorming con utente)

## Obiettivo

L'importo mostrato in primo piano deve essere quello nella valuta in cui la
spesa è stata realmente sostenuta; la conversione in EUR scende a informazione
secondaria. Riferimenti: collaudo su dispositivo reale (`ToDo.md` fase 6b,
BUG-01), `Specifiche.md` §3 "Valuta Multipla".

Emerso dal collaudo: con `importo_eur` NULL (rete assente in release) tutte le
schermate mostravano `€ 0,00` pur avendo spese registrate. Oltre al bug del
permesso INTERNET (già corretto, v0.7.2), la gerarchia di visualizzazione è
sbagliata: l'app dà rilievo a un dato derivato e opzionale invece che al dato
inserito dall'utente.

## Decisioni prese (con l'utente)

1. **Trasferta multi-valuta → una riga per valuta** come importo primario (in
   pratica quasi sempre una sola riga). Nessun caso speciale, nessuna
   informazione persa.
2. **Lista trasferte**: le card mostrano i totali nella/e valuta/e della loro
   trasferta; il "Totale complessivo" resta in EUR, unica base comune tra
   trasferte con valute diverse.
3. **Riepilogo per categoria**: valuta originale se la trasferta ha una sola
   valuta, altrimenti EUR come oggi.
4. **L'EUR non compare quando vale zero perché manca la conversione**: meglio
   assente che uno `0,00` che sembra un totale azzerato.

Nessuna modifica allo schema DB e nessuna migrazione: i dati necessari
(`spese.importo`, `spese.valuta`) sono già presenti.

## Componenti

### 1. `lib/core/utils/formatters.dart`

```dart
/// Importo con simbolo e decimali della valuta ISO indicata.
/// Valuta fuori dall'enum Currency → prefisso col codice ISO, 2 decimali.
String formatValuta(double value, String codeIso);

String formatEur(double value) => formatValuta(value, 'EUR');
```

Esempi: `formatValuta(45320, 'JPY')` → `¥ 45.320` (0 decimali),
`formatValuta(12.5, 'EUR')` → `€ 12,50`, `formatValuta(10, 'XXX')` → `XXX 10,00`.

### 2. `lib/data/repositories/spesa_repository.dart`

Nuovo metodo accanto agli esistenti:

```dart
/// Totali per categoria nella valuta originale (SUM(importo)).
/// Da usare solo quando la trasferta ha una sola valuta: altrimenti
/// sommerebbe importi non omogenei.
Future<Map<Categoria, double>> totaliPerCategoria(int trasfertaId);
```

`totaliPerValuta`, `totaleEur`, `countSenzaEur` e `totaliEurPerCategoria`
restano invariati.

### 3. `lib/ui/trasferte/trasferta_detail_controller.dart`

- Nuovo getter `String? valutaUnica` → la valuta se `totaliPerValuta.length == 1`,
  altrimenti `null`.
- `load()` popola un unico campo `totaliPerCategoria` dal repository giusto in
  base a `valutaUnica`: metodo in valuta originale se `valutaUnica != null`,
  `totaliEurPerCategoria` altrimenti. La UI distingue i due casi guardando
  `valutaUnica`, senza flag aggiuntivi.

### 4. `lib/ui/trasferte/trasferta_detail_screen.dart` — `_TotalsHeader`

```
Totale trasferta
¥ 45.320
€ 12,50                        ← una riga per valuta, headlineMedium
───────────────────────────
≈ € 271,42                     ← bodySmall, solo se totaleEur > 0
2 spese senza conversione EUR  ← invariato
```

- Ordine righe: valuta di default della trasferta per prima, poi le altre per
  importo decrescente.
- `totaliPerValuta` vuoto (nessuna spesa) → riga unica
  `formatValuta(0, trasferta.valutaDefault)`.
- La riga `≈ €` non viene costruita se `totaleEur == 0` né quando l'unica
  valuta è già EUR (sarebbe la ripetizione della riga primaria).
- Sezione categorie: il titolo dichiara sempre la valuta usata —
  `Totali per categoria (JPY)` con valuta unica, `Totali per categoria (EUR)`
  nel caso multi-valuta (etichetta odierna, invariata).

### 5. `lib/ui/trasferte/trasferte_list_controller.dart` + `trip_card.dart`

`TrasfertaListItem` porta anche `Map<String, double> totaliPerValuta`. La card
sostituisce `formatEur(item.totaleEur)` con le righe per valuta (stesse regole
di ordinamento dell'header) più `≈ € x` in piccolo quando `totaleEur > 0`.

Il controller espone inoltre `int countSenzaEurTotale`, somma delle spese non
convertite di tutte le trasferte non archiviate.

### 6. `lib/ui/trasferte/trasferte_list_screen.dart` — `_TotalHeader`

Resta in EUR. Quando `countSenzaEurTotale > 0` aggiunge sotto, in piccolo:
`esclude N spese senza conversione`.

## Test

| Livello | Copertura |
|---|---|
| unit | `formatValuta`: JPY (0 decimali), EUR, KWD (3 decimali), codice ignoto |
| unit | `SpesaRepository.totaliPerCategoria`: somma per categoria in valuta originale, spese di altre trasferte escluse |
| unit | `TrasfertaDetailController`: `valutaUnica` con una/più valute; scelta della sorgente categorie |
| unit | `TrasferteListController`: `totaliPerValuta` per item, `countSenzaEurTotale` |
| widget | header dettaglio: valuta singola, due valute, nessuna spesa, `totaleEur == 0` → nessuna riga `≈ €` |
| widget | `TripCard`: riga in valuta originale + `≈ €`; senza conversione niente riga EUR |
| widget | header lista: nota `esclude N spese senza conversione` |

Il caso "nessuna conversione disponibile" è il test di regressione diretto del
sintomo osservato sul dispositivo (`€ 0,00` al posto del totale reale).

## Fuori scope

- Export CSV/PDF (fase 7): la scelta delle colonne valuta si decide lì.
- Ricalcolo automatico delle spese già salvate con `importo_eur` NULL: resta
  manuale col pulsante di ricalcolo nel form (decisione fase 6, punto 2).
- Serbo cirillico e valute fuori dal set ECB (RSD, AED): invariati, restano
  senza conversione automatica.
