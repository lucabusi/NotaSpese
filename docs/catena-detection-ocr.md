# Valutazione catena detection → OCR per scontrini (integrazione fase 0a)

**Data:** 2026-07-15 · **Ambito:** stadio di localizzazione scontrino (YOLOv8n vs MobileNetV3-Small) × stadio OCR (PaddleOCR vs ML Kit) · **Verdetto:** ✅ nessun detector custom — **ML Kit Document Scanner → ML Kit Text Recognition v2**; PaddleOCR solo come opzione mirata per il cirillico

---

## 1. Ruolo dei due stadi nel progetto

- **Detection:** trovare/ritagliare lo scontrino nella foto (bounding box + deskew) prima dell'OCR. Nel piano attuale è coperto da inquadratura manuale + `image_cropper`.
- **OCR:** immagine ritagliata → testo grezzo, poi parser/LLM per i campi.

## 2. Stadio detection: YOLOv8n vs MobileNetV3-Small

| Criterio | YOLOv8n | MobileNetV3-Small (come detector: SSDLite-MNv3) |
|---|---|---|
| Velocità inferenza | ~20–50 ms (int8/NNAPI, dipende dal device) | ~15–40 ms |
| Disco | fp32 12,2 MB · **int8 ~3,3 MB** | ~4–7 MB (SSDLite) |
| Difficoltà installazione (Flutter) | media-alta: export TFLite, post-processing NMS manuale (output `[1,9,8400]`, notoriamente ostico), `tflite_flutter` | media: stessa via TFLite, post-processing SSD più standard |
| Training richiesto | ⚠️ **sì** — nessun modello pre-addestrato "scontrini": serve dataset etichettato + training custom | ⚠️ sì — MobileNetV3-Small da solo è un **classificatore**, non localizza: serve la variante SSDLite e comunque training custom |
| Licenza | 🔴 **AGPL-3.0** — per un'app distribuita obbliga a rilasciare i sorgenti sotto AGPL o comprare licenza commerciale Ultralytics | 🟢 Apache-2.0 |

**Il punto decisivo:** entrambi richiedono **dataset etichettato e training custom** (giorni di lavoro) per un problema — "trova il documento nella foto" — che Android risolve già gratis:

### Alternativa che azzera lo stadio: ML Kit Document Scanner
- Plugin Flutter (`google_mlkit_document_scanner`, verificato su pub.dev: v0.5.0, publisher flutter-ml.dev), consegnato via Google Play Services → **~0 MB nell'APK**, zero training, zero modello custom.
- Fa detection bordi + crop + deskew + UI di conferma in un colpo solo; **non richiede nemmeno il permesso camera nell'app** (gestito da Play Services); si aggancia esattamente dove il piano prevede `image_cropper`.
- Velocità: interattivo/real-time; difficoltà installazione: banale (stesso ecosistema ML Kit già in uso). ⚠️ API in beta e solo Android — accettabile: il progetto è Android-only; tenere `image_picker`+`image_cropper` come percorso di riserva se la beta desse problemi.

**Verdetto detection:** né YOLOv8n né MobileNetV3 — usare **ML Kit Document Scanner** (fase 4), con `image_cropper` come ritocco manuale opzionale già previsto. Se in futuro servisse davvero un detector custom (es. multi-scontrino in una foto): SSDLite-MobileNetV3 per la licenza Apache, mai YOLOv8n senza licenza commerciale.

## 3. Stadio OCR: PaddleOCR vs ML Kit Text Recognition v2

| Criterio | PaddleOCR (PP-OCRv4 mobile) | ML Kit Text Recognition v2 |
|---|---|---|
| Velocità | ~100–500 ms su ARM (Paddle-Lite, NEON) — stima | ~50–300 ms — stima; NNAPI/GPU gestito da Play Services |
| Disco | det ~4,7 MB + cls ~1,4 MB + **rec ~10 MB per script** → IT/EN/DE (latin) + JA + cirillico ≈ **35–40 MB** nell'APK | **unbundled: ~260 KB per script** (modelli in Play Services); bundled: ~4 MB/script |
| Difficoltà installazione (Flutter) | 🔴 **alta**: nessun plugin Flutter ufficiale → integrazione nativa Paddle-Lite (AAR + JNI) + method channel custom, conversione modelli `.nb`, manutenzione a carico nostro | 🟢 **banale**: `google_mlkit_text_recognition` (plugin ufficiale, già nel piano) |
| Lingue del progetto | 🟢 tutte: latin + japanese + **cyrillic** (SR cirillico coperto) | ⚠️ Latin, Chinese, Devanagari, Japanese, Korean — **niente cirillico**: serbo in cirillico non riconosciuto (serbo in latinica sì) |
| Licenza | Apache-2.0 🟢 | Proprietaria Google, gratuita, richiede Play Services |
| Offline | ✅ (modelli nell'APK) | ✅ (dopo download modello via Play Services) |

**Verdetto OCR:** **ML Kit v2 confermato** come motore unico v1.0 — vince su disco (≈0 vs ~35-40 MB), installazione (plugin ufficiale vs integrazione nativa custom) e velocità comparabile. PaddleOCR ha un solo vantaggio concreto: il **cirillico**. Gap accettato per v1.0: gli scontrini serbi sono spesso in latinica; se all'uso reale il cirillico risultasse frequente → gli scontrini SR possono passare dal motore Claude (Haiku legge il cirillico) oppure si valuta l'integrazione PaddleOCR *solo cyrillic* in v1.1.

## 4. Confronto delle 4 catene richieste

| Catena | Velocità totale | Disco extra | Difficoltà install | Note bloccanti |
|---|---|---|---|---|
| YOLOv8n → ML Kit | ~150–350 ms | ~3–12 MB | media-alta | AGPL + training custom |
| YOLOv8n → PaddleOCR | ~150–550 ms | ~40–52 MB | alta | AGPL + training + integrazione nativa |
| MobileNetV3 → ML Kit | ~150–340 ms | ~4–7 MB | media | training custom (SSDLite) |
| MobileNetV3 → PaddleOCR | ~150–540 ms | ~40–47 MB | alta | training + integrazione nativa |
| **⭐ Doc Scanner → ML Kit v2** | **~100–350 ms** | **~0 MB** | **bassa** | gap cirillico (mitigato da Claude/v1.1) |

⚠️ Le latenze sono stime da benchmark pubblici su hardware eterogeneo — la misura vera è sul dispositivo target (stesso gate di fase 5).

## 5. Impatti sul piano

- **Fase 4 (camera):** aggiunto `google_mlkit_document_scanner` come primo passo del flusso scatto (detection+crop+deskew automatici); `image_cropper` resta per il ritocco manuale.
- **Fase 5 (OCR):** ML Kit v2 confermato; annotato il gap cirillico con mitigazione (motore Claude per scontrini SR in cirillico; PaddleOCR-cyrillic eventuale in v1.1).
- **Nessun task di training modelli**: eliminato il rischio di giorni di lavoro su dataset/training per un problema già risolto dalla piattaforma.

## Fonti

- [YOLOv8n — Qualcomm AI Hub (12,2 MB fp32 / 3,25 MB int8)](https://aihub.qualcomm.com/models/yolov8_det) · [Licenza Ultralytics AGPL-3.0](https://www.ultralytics.com/license) · [Export TFLite](https://docs.ultralytics.com/integrations/tflite) · [Output shape issue Android](https://github.com/ultralytics/ultralytics/issues/2950)
- [PP-OCRv4 mobile det](https://huggingface.co/PaddlePaddle/PP-OCRv4_mobile_det) · [PP-OCRv4 mobile rec](https://huggingface.co/PaddlePaddle/PP-OCRv4_mobile_rec) · [Model list (dimensioni per script)](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version2.x/ppocr/model_list.en.md) · [Mobile/edge deployment Paddle-Lite](https://deepwiki.com/PaddlePaddle/PaddleOCR/6.6-mobile-and-edge-deployment)
- [ML Kit Text Recognition v2 — lingue supportate](https://developers.google.com/ml-kit/vision/text-recognition/v2/languages) · [v2 Android (bundled ~4 MB vs unbundled ~260 KB per script)](https://developers.google.com/ml-kit/vision/text-recognition/v2/android) · [Plugin Flutter](https://pub.dev/packages/google_mlkit_text_recognition)
