# Ritaglio dello scontrino dopo lo scatto — Design

Data: 2026-07-21 · Stato: approvato (brainstorming con utente)

## Obiettivo

Dopo lo scatto e prima che l'immagine venga passata all'OCR e salvata,
l'utente può ritagliarla. Serve quando il rilevamento automatico del
Document Scanner sbaglia i bordi o quando si è usato il percorso di riserva
(`image_picker`), che non ritaglia nulla: il testo di contorno che finisce
nell'inquadratura peggiora il parsing e gonfia la foto salvata.

## Decisioni prese (con l'utente)

1. **Schermata di ritaglio in-app**, widget Flutter puro sopra il pacchetto
   `image` già usato da `PhotoService`. Nessuna dipendenza nativa nuova:
   la build Android non è verificabile su questa macchina (JDK 11, SDK
   incompleto — gotcha in `CLAUDE.md`), quindi introdurre una activity
   nativa significherebbe scoprire i problemi solo dopo il push. Con Dart
   puro l'intera pipeline resta testabile su host, come `PhotoService`.
2. **Compare sempre**, con il rettangolo già impostato sull'immagine intera:
   se lo scanner ha ritagliato bene basta confermare. Un solo comportamento,
   nessun ramo da ricordare.
3. **Ambito: il flusso "scatta scontrino"** (`_scattaEOcr`), l'unico in cui
   l'immagine passa dal parser. Il ritaglio avviene una volta sola, prima
   dell'OCR: il testo riconosciuto e la foto salvata riguardano lo stesso
   ritaglio.

## Componenti

### 1. `lib/services/photo/crop_service.dart`

```dart
/// Ritaglio in frazioni 0..1 dell'immagine decodificata, così la UI può
/// ragionare in coordinate di schermo senza conoscere i pixel reali.
class CropRect {
  const CropRect({required this.left, required this.top,
                  required this.right, required this.bottom});
  static const CropRect full = CropRect(left: 0, top: 0, right: 1, bottom: 1);

  final double left, top, right, bottom;

  bool get isFull;            // tolleranza: nessun ritaglio percettibile
  CropRect clamped();         // dentro 0..1, lati ordinati, lato minimo 5%
}

/// Scrive il ritaglio in un file jpg temporaneo e ne restituisce il path.
/// Con [CropRect.full] restituisce [sourcePath] invariato: nessuna
/// ricodifica, nessuna perdita di qualità quando non si ritaglia.
class CropService {
  Future<String> crop(String sourcePath, CropRect rect);
}
```

Qualità di ricodifica alta (95): questo file è un intermedio, la
compressione vera la applica `PhotoService.process` a valle.

### 2. `lib/ui/foto/crop_screen.dart`

`CropScreen.show(context, imagePath:, cropService:)` → path ritagliato, o
`null` se l'utente annulla.

- Immagine in `BoxFit.contain` dentro un `LayoutBuilder`; il rettangolo di
  ritaglio vive in coordinate del box visualizzato e viene convertito in
  frazioni solo alla conferma.
- Rettangolo iniziale = immagine intera. Quattro maniglie d'angolo
  trascinabili + trascinamento del corpo; l'esterno è oscurato.
- Azioni: `Annulla` (torna indietro, nessun file scritto) e `Conferma`.

### 3. Aggancio in `lib/ui/trasferte/trasferta_detail_screen.dart`

In `_scattaEOcr`, tra la cattura e l'OCR:

```dart
final path = await _captureScatta();
if (path == null || !mounted) return;
final cropped = await CropScreen.show(context, imagePath: path, ...);
if (cropped == null || !mounted) return;   // annullato: si torna al dettaglio
```

Da lì in poi `cropped` sostituisce `path` ovunque: OCR, `pendingFoto` del
form e callback "riprova altro motore".

## Test

| Livello | Copertura |
|---|---|
| unit | `CropRect.clamped`: valori fuori 0..1, lati invertiti, lato sotto il minimo |
| unit | `CropRect.isFull` con tolleranza |
| unit | `CropService.crop` su uno scontrino reale di `scontrini_training/`: dimensioni attese del file prodotto, immagine decodificabile, sorgente intatta |
| unit | `CropService.crop` con `CropRect.full` → stesso path, nessun file nuovo |
| widget | `CropScreen`: mostra l'immagine, Annulla → null, Conferma senza modifiche → path invariato, trascinamento di una maniglia → ritaglio effettivo più piccolo, trascinamento del corpo → traslazione senza ridimensionare, resize del box (rotazione) → il ritaglio resta la stessa frazione |
| widget | dettaglio trasferta: scatta → compare il crop → conferma → l'OCR riceve il path ritagliato; annullo del crop → nessun OCR, nessun form |

Gotcha noti da rispettare (memoria di progetto): l'IO reale nel corpo di
`testWidgets` non completa mai (FakeAsync) — i file vanno preparati in
`setUp`, e l'IO innescato da un tap va avvolto in `tester.runAsync`.

## Fuori scope

- Rotazione, raddrizzamento prospettico, regolazione contrasto: il
  Document Scanner li fa già sul percorso principale; il resto è v1.1
  (hook già annotato in `ReceiptCaptureService`).
- Ritaglio della foto aggiunta dal form spesa ("Aggiungi foto"): quella non
  passa dal parser.
- Ritaglio di foto già salvate.

## Limiti noti

- Decode/crop girano sul thread principale, dietro un dialog di progresso
  bloccante (non su isolate): a schermo resta comunque ferma per la durata
  dell'operazione. Non spostato su isolate perché serve una misura reale
  su device per giustificarne la complessità (canale nativo, marshalling
  dei byte) — nessun dato oggi indica che sia necessario.
- Trascinare una maniglia oltre l'angolo opposto scambia gli angoli
  (es. l'angolo in alto a sinistra diventa quello in basso a destra)
  invece di fermarsi sul bordo: comportamento tollerato, non un bug da
  fixare in questa fase.
