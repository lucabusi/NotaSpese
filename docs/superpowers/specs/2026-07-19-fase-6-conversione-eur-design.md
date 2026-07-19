# Fase 6 — Multi-valuta / conversione EUR — Design

Data: 2026-07-19 · Stato: approvato (brainstorming con utente)

## Obiettivo

Conversione automatica in EUR delle spese in valuta estera via `frankfurter.app`
(API pubblica, no key), mai bloccante, con controllo esplicito dell'utente.
Riferimenti: `ToDo.md` fase 6, `Specifiche.md` §3 "Valuta Multipla".

## Decisioni prese (con l'utente)

1. **Tasso alla data della spesa** (storico: `GET /{yyyy-MM-dd}?from=X&to=EUR`).
   Weekend/festivi: frankfurter risponde con l'ultimo giorno lavorativo precedente.
2. **Mai ricalcolo automatico su modifica** di una spesa esistente: `importo_eur`
   resta com'è anche se cambiano importo/valuta/data. Aggiornamento SOLO tramite
   pulsante di ricalcolo manuale nel form.
3. **Conversione live nel form** (non al salvataggio): importo+valuta inseriti →
   debounce → fetch → campo EUR pre-compilato con badge AUTO, visibile e
   correggibile prima di salvare.

## Approccio scelto

**Fetch diretto senza cache persistente** + cache in-memory di sessione
`(data, valuta) → tasso` per evitare richieste duplicate durante l'editing.
Scartati: cache persistente in DB (beneficio quasi nullo a 60-90 spese/mese) e
prefetch giornaliero (over-engineering).

## Componenti

### 1. `lib/services/currency/exchange_service.dart`

```dart
class ExchangeResult {
  final double amountEur;
  final double rate; // 1 unità valuta origine = rate EUR
}

class ExchangeService {
  ExchangeService({http.Client? client, SettingsService settings});
  Future<ExchangeResult?> convert({
    required double amount,
    required String from,   // ISO 4217
    required DateTime date, // data della spesa
  });
}
```

- Ritorna `null` per QUALSIASI fallimento: offline (`SocketException`),
  timeout (5 s), HTTP non-200, JSON malformato, valuta non supportata da
  frankfurter. Mai throw verso la UI, mai bloccante (coerente con fase 5).
- `from == 'EUR'` → corto-circuito: `rate = 1.0`, nessuna chiamata rete.
- Rispetta il toggle `tassi_online` di `SettingsService`: se OFF → `null`
  immediato, nessuna chiamata.
- Cache in-memory `{(yyyy-MM-dd, valuta): rate}` valida per la sessione.
- `http.Client` iniettabile → unit test con `MockClient`.
- Endpoint: `https://api.frankfurter.app/{yyyy-MM-dd}?from={valuta}&to=EUR`.

### 2. Form spesa — conversione live

- Trigger: valuta estera selezionata E importo valido inserito → debounce
  ~600 ms → `convert()`.
- Successo → campo EUR pre-compilato + badge **AUTO** + tasso in piccolo
  (es. "1 JPY = 0,0061 €").
- Edit manuale del campo EUR → badge sparisce, stato diventa manuale.
- Fallimento/offline → campo vuoto ed editabile, nessun errore bloccante
  (al più testo neutro "tasso non disponibile").
- Pulsante ricalcolo (icona refresh accanto al campo EUR): forza nuova
  conversione e sovrascrive anche un valore manuale (azione esplicita).
- Modifica spesa esistente: nessuna conversione automatica all'apertura né al
  salvataggio (decisione 2); il pulsante ricalcolo è l'unica via.
- Cambio valuta a EUR: comportamento fase 3 invariato (campo EUR nascosto,
  `importo_eur = importo`).

### 3. Stato al salvataggio

| Stato campo EUR   | `importo_eur` | `tasso_cambio` |
|-------------------|---------------|----------------|
| AUTO (badge)      | valore auto   | tasso usato    |
| Manuale (editato) | valore utente | NULL           |
| Vuoto             | NULL          | NULL           |

Nessuna chiamata rete al save: la conversione è già avvenuta live nel form.
Schema DB invariato (colonne già presenti dalla fase 1).

### 4. Totali trasferta

- Somma EUR esistente invariata; spese senza `importo_eur` escluse dal totale
  EUR con indicazione esplicita: "≈ € 123,45 · 3 spese senza EUR".

### 5. Impostazioni

- Toggle "Tassi di cambio online" in `ImpostazioniMinimal`, default ON,
  persistito in `SettingsService` (`SharedPreferences`, chiave `tassi_online`).

## Error handling

Ogni fallimento rete/parse → `null` silenzioso; il flusso di inserimento spesa
non è mai bloccato dalla conversione. Nessun log della risposta con dati
sensibili (non ce ne sono: solo tassi pubblici).

## Test

- **Unit `ExchangeService`** (`MockClient`): successo con tasso storico, EUR
  corto-circuito senza rete, timeout, HTTP 404/500, `SocketException`, JSON
  malformato, cache hit (seconda chiamata stessa data+valuta senza fetch),
  toggle OFF → null senza fetch.
- **Widget test form**: pre-fill AUTO con badge dopo debounce, edit manuale →
  badge rimosso e `tasso_cambio` NULL al save, pulsante ricalcolo sovrascrive,
  offline → campo vuoto e save senza EUR, spesa esistente riaperta → nessun
  fetch automatico.
- **Unit totali**: trasferta con mix spese con/senza EUR → totale e conteggio
  escluse.

## Fuori scope

- Cache persistente tassi, valute multiple di destinazione (solo EUR),
  ricalcolo batch di spese esistenti, tassi in export (fase 7 li leggerà dal DB).
