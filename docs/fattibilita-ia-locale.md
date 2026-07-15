# Studio di fattibilità — Motore riconoscimento scontrini (fase 0a)

**Data:** 2026-07-15 · **Versione:** 2 (rivalutazione: esclusi i NO-GO della v1, aggiunti Claude API e versioni minimali di modelli open-source) · **Verdetto:** ✅ **GO confermato** per l'architettura ibrida B con shortlist di modelli intercambiabili + raccomandazione modello per il motore Claude API

---

## 1. Contesto e requisiti

Invariati dalla v1:

| Requisito | Valore |
|---|---|
| Funzionamento motore locale | 100% offline |
| Lingue scontrini | IT · EN · JA · SR · DE |
| Campi da estrarre | importo totale, fornitore, data (+ inferenza valuta) |
| Volume | 60–90 scontrini/mese |
| Latenza accettabile | ≤ ~10 s per scontrino |
| Dispositivo target | Android 13+, RAM non garantita ≥8 GB |
| Budget storage di riferimento | foto ≈ 420 MB/anno |

**Architettura di riferimento:** ML Kit fa l'OCR (immagine → testo, on-device, gratis); il valore aggiunto di IA (locale o cloud) è l'**estrazione dei campi strutturati**. Il parser regex resta sempre come fallback.

## 2. Esclusi dalla v1 (non rivalutati)

| Candidato | Motivo esclusione (v1) |
|---|---|
| VLM end-to-end Gemma 3n E2B/E4B | ~3 GB disco (≈7 anni di budget foto), RAM 2,7–3,4 GB → richiede flagship |
| Donut fine-tuned CORD | dataset scontrini indonesiani (no IT/JA/SR/DE), nessun port mobile, ~800 MB |
| LayoutLM/LayoutXLM, PaddleOCR-KIE | pipeline complesse server-side, nessun deployment mobile pronto |

## 3. Candidati valutati (v2)

### B — Ibrido: OCR ML Kit + LLM testo locale ⭐ (confermato, ora con shortlist)

Tutti i candidati sotto girano sullo **stesso runtime** (MediaPipe LLM Inference / LiteRT-LM, plugin Flutter `flutter_gemma`, formato `.task`/`.litertlm` da `litert-community` su Hugging Face). Cambiare modello = cambiare file scaricato: il gate benchmark di fase 5 può provarli tutti a costo quasi nullo.

| Modello | Disco (quantizzato) | RAM stimata | Note |
|---|---|---|---|
| **Gemma 3 1B int4** (primario) | **~529 MB** (verificato) | ~1–1,5 GB | prefill fino a ~2.585 tok/s; multilingue; il candidato v1 |
| **Qwen2.5 1.5B int4/int8** | ~1–1,6 GB (stima) | ~1,5–2 GB | il più forte su **JA** e CJK in questa classe — candidato se Gemma delude sul giapponese |
| **Llama 3.2 1B int4** | ~0,7–0,8 GB (stima) | ~1–1,5 GB | alternativa consolidata; multilingua ok ma CJK più debole |
| **Qwen2.5 0.5B int8** | ~0,5 GB (stima) | <1 GB | opzione ultra-minimale; qualità estrazione da verificare, rischio errori su layout rumorosi |

- **Latenza (tutti):** prefill del testo scontrino (200–600 token) + decode JSON (~80–120 token) → **~2–5 s stimati** su hardware recente. ⚠️ Stime da benchmark pubblici — conferma al gate di fase 5.
- **Giudizio:** **GO confermato.** Modello primario Gemma 3 1B; Qwen2.5 1.5B come secondo da provare al gate specificamente sulle fixture JA/SR; gli altri due solo se servono compromessi di spazio.

### Nuovo — SmolVLM 256M/500M (VLM open-source minimali, immagine→testo diretto)

I più piccoli VLM esistenti (256M = il più piccolo al mondo), pensati per edge.

- **Qualità documenti:** OCRBench 52,6% (256M) / 61,0% (500M); DocVQA 58,3% / 70,5% — **insufficiente per estrazione affidabile da scontrini** (layout rumorosi, 5 lingue).
- **Toolchain:** transformers / MLX / ONNX — **nessun runtime Flutter/Android di prima classe** (no formato `.task`), integrazione custom via onnxruntime.
- **Giudizio:** **NO-GO v1.0** — qualità e toolchain immaturi per questo caso d'uso. Da riguardare in futuro (SmolVLM2 e successori migliorano rapidamente).

### Nuovo — Claude API come motore di confronto (già previsto come "Claude Vision")

Il motore cloud era già in spec; la rivalutazione fissa **modello, tecnica e costi**.

- **Modello raccomandato: `claude-haiku-4-5`** — supporta vision, è il più economico ($1/$5 per MTok) e più che sufficiente per estrazione campi da scontrino. Upgrade selezionabile: `claude-opus-4-8` per scontrini difficili (5×–7× il costo).
- **Tecnica:** invio immagine (base64) + **structured outputs** (`output_config.format` con `json_schema`) → JSON dei campi **garantito valido e parseabile**: elimina alla radice la fragilità del parsing, cosa che nessun motore locale garantisce.
- **Costo stimato per scontrino** (foto 1920px compressa ≈ 1.500–2.500 token immagine + prompt ~200 token, output ~100 token): Haiku 4.5 ≈ **$0,002–0,004** → a 90 scontrini/mese ≈ **$0,20–0,35/mese** (Opus 4.8: ≈ $1,–1,8/mese). Costo di fatto trascurabile.
- **Latenza:** ~2–6 s (rete inclusa). **Vincoli:** richiede rete + API key (già gestita in spec: `flutter_secure_storage`, fallback automatico a ML Kit se offline).
- **Giudizio:** **motore di riferimento per qualità** — è il metro di paragone del gate: il motore locale ha senso solo dove Claude non arriva (offline). Aggiornare la spec: modello di default Haiku 4.5 + structured outputs.

### Confermati dalla v1 (invariati)

- **C2 — Fine-tune Gemma 3 270M** su dataset scontrini proprio (~300 MB int8, QLoRA su Colab): **v1.1**, da attivare se il gate fallisce o se JA/SR deludono.
- **D — Gemini Nano di sistema** (ML Kit Prompt API): zero storage, ma device gating (ottimale Pixel 10) → **bonus opportunistico** se `checkFeatureStatus()` è disponibile.

## 4. Tabella comparativa (v2)

| | **B — ML Kit + Gemma 3 1B** ⭐ | B-alt — Qwen2.5 1.5B | SmolVLM 256/500M | **Claude API (Haiku 4.5)** | C2 — 270M fine-tuned | D — Gemini Nano |
|---|---|---|---|---|---|---|
| Disco | **~529 MB** | ~1–1,6 GB | ~0,3–1 GB | 0 | ~300 MB | 0 (sistema) |
| RAM picco | ~1–1,5 GB | ~1,5–2 GB | ~1 GB+ | — | <0,5 GB | gestita da AICore |
| Latenza/scontrino | ~2–5 s (stima) | ~3–6 s (stima) | non provata su mobile | ~2–6 s (rete) | ~1–2 s | ~2–5 s |
| Costo ricorrente | 0 | 0 | 0 | **~$0,2–0,35/mese** | 0 (training una tantum) | 0 |
| Offline | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Lingue IT/EN/JA/SR/DE | ✅ (JA da validare) | ✅ (forte su JA) | ❌ (OCRBench ~52-61%) | ✅ | dipende dal dataset | ✅ (EN meglio) |
| JSON garantito valido | ❌ (fallback regex) | ❌ (fallback regex) | ❌ | ✅ **structured outputs** | ❌ | ❌ |
| Integrazione Flutter | `flutter_gemma` | `flutter_gemma` (stesso runtime) | runtime custom ONNX | `http` + API | `flutter_gemma` | canale nativo ML Kit |
| Disponibilità garantita | ✅ | ✅ | ✅ | solo online + key | ✅ | ❌ device gating |
| Verdetto v1.0 | **GO (primario)** | GO (riserva JA/SR al gate) | NO-GO | ✅ motore cloud (già in spec, ora con modello fissato) | v1.1 | bonus opzionale |

## 5. Verdetto e condizioni (v2)

**GO confermato per l'architettura B**, rafforzato dalla shortlist: `LocalAiOcrService` = ML Kit OCR → LLM locale via `flutter_gemma` → JSON → form di conferma. Condizioni:

1. **Modello NON bundlato nell'APK**: download on-demand dalle Impostazioni (Gemma 3 1B ~529 MB, avviso Wi-Fi), eliminabile. App pienamente funzionante senza (ML Kit + regex).
2. **Gate benchmark in fase 5** su dispositivo reale con 3–5 scontrini veri, ora **comparativo**: Gemma 3 1B e, sulle fixture JA/SR, Qwen2.5 1.5B (stesso runtime, costo di prova ~zero). Criteri: latenza mediana ≤10 s, no OOM, importo+data corretti ≥80% su IT/EN. Riferimento di qualità: stesso set su Claude Haiku 4.5. Gate fallito su tutti i modelli → motore nascosto, C2 in valutazione per v1.1.
3. **Fallback sempre attivo**: JSON non valido o modello assente → parser regex, mai bloccare il flusso.
4. **Prompt few-shot versionato** (`local_ai_prompt.dart`), esempi per lingua, validato dalle fixture del parser; **stesso prompt/schema riusato dal motore Claude** (con structured outputs) per confrontare mele con mele.
5. **Motore Claude (nuovo, da questa rivalutazione):** modello di default `claude-haiku-4-5`, structured outputs con `json_schema` dei campi, `max_tokens` contenuto; selettore modello avanzato (Haiku/Opus) opzionale in Impostazioni.

**Nota di onestà sui numeri:** dimensione Gemma 3 1B, prezzi Claude e benchmark SmolVLM sono dati pubblicati/verificati; dimensioni Qwen/Llama e tutte le latenze locali sono **stime** da confermare al gate (punto 2).

## 6. Impatti sul piano

- **Fase 5:** gate benchmark diventa comparativo (Gemma 3 1B + Qwen2.5 1.5B su JA/SR, riferimento Claude Haiku); `ClaudeOcrService` fissa modello `claude-haiku-4-5` + structured outputs.
- **Fase 8:** gestione modello locale invariata (download/elimina/stato); la scelta del file modello segue l'esito del gate.
- **v1.1 backlog:** invariato (C2 fine-tune 270M; SmolVLM-class da riguardare quando maturerà un runtime mobile).
- **Effort:** invariato (+1,5 g fase 5; il confronto multi-modello riusa lo stesso codice).

## Fonti

**Modelli locali**
- [Gemma 3 1B LiteRT (529 MB, prefill 2585 tok/s)](https://huggingface.co/litert-community/Gemma3-1B-IT) · [Gemma 3 on mobile — Google AI Edge](https://developers.googleblog.com/gemma-3-on-mobile-and-web-with-google-ai-edge/)
- [litert-community/Qwen2.5-1.5B-Instruct](https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct) · [litert-community/Phi-4-mini-instruct](https://huggingface.co/litert-community/Phi-4-mini-instruct)
- [LiteRT-LM (supporta Gemma, Llama, Phi-4, Qwen)](https://github.com/google-ai-edge/LiteRT-LM) · [MediaPipe LLM Inference — Android](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android)
- [flutter_gemma (pub.dev)](https://pub.dev/packages/flutter_gemma)
- [SmolVLM 256M/500M — Hugging Face blog](https://huggingface.co/blog/smolervlm) · [SmolVLM paper (benchmark OCRBench/DocVQA)](https://arxiv.org/pdf/2504.05299)
- [Gemma 3 270M](https://developers.googleblog.com/en/introducing-gemma-3-270m/) · [Fine-tune 270M on-device](https://developers.googleblog.com/own-your-ai-fine-tune-gemma-3-270m-for-on-device/)
- [ML Kit GenAI / Prompt API](https://developers.google.com/ml-kit/genai) · [Gemini Nano device support](https://developer.android.com/ai/gemini-nano)

**Claude API** (da documentazione ufficiale Anthropic, skill claude-api 2026)
- Prezzi: Haiku 4.5 $1/$5 per MTok, Opus 4.8 $5/$25 per MTok
- Vision (immagini base64) + structured outputs (`output_config.format`, `json_schema`) per JSON garantito

**Esclusi v1:** [Gemma 3n E2B LiteRT](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) · [donut-base-finetuned-cord-v2](https://huggingface.co/naver-clova-ix/donut-base-finetuned-cord-v2)
