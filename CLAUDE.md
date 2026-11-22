# KitaKo — Claude Migration Guide

This file is read automatically by Claude Code on every session. It covers the
branch layout, what the app contains, where models live, and the exact steps
needed to get a fresh clone working on a new machine.

---

## 1. Branches

**`master`** is the release line (app version `1.0.0+1`). Work from `master`
unless explicitly switching.

| Branch | Purpose |
|--------|---------|
| `master` | Release line: ONNX pipeline, EULA + permission onboarding, resizable gallery |
| `v2-system-ric` | Dev branch: renders the `personal_1k` test dataset instead of the real gallery; launcher label `KitaKo_dev` |
| `deployment` | Play Store prep; also deletes the face + alpha-test code that `master` only unroutes |
| `feat/face_recognition`, `feat/siglip1-aligned-embeddings`, `feature/onnx-embedding-improvements`, `feature/metadata-filter`, `ann-algo` | Historical feature work, superseded by `master` (not merged commit-for-commit) |

---

## 2. What the app contains

### Embedding pipeline (ONNX)
- **`packages/kitako_embedding/`**
  - `OnnxEmbeddingService` (`onnx_embedding_service.dart`)
  - `SiglipInference` (`siglip_inference.dart`) — ONNX Runtime image + text encoder
  - `GemmaTokenizer` (`gemma_tokenizer.dart`) — 256K-vocab SentencePiece BPE tokenizer
    aligned to HuggingFace `tokenizer.json` (no lowercasing, no leading ▁, right-pad)
  - `ImagePreprocessor` — `preprocessRgbaAsync` / `preprocessRgbaInIsolate`
    for pre-decoded RGBA input (avoids re-decoding JPEG in isolate)
  - Face sub-package: `face_pipeline.dart`, `onnx_face_detector.dart` (SCRFD-2.5G),
    `onnx_face_embedder.dart` (ArcFace MobileFaceNet), `face_aligner.dart` (Umeyama),
    `face_dbscan.dart` (DBSCAN clustering)
- **`packages/kitako_core/`** — shared types, incl. face constants
  (`kFaceEmbeddingDim=512`, `kFaceInputSize=112`, `kFaceDetectorInputSize=640`,
  `kFaceClusteringThreshold=0.45`)
- **`packages/kitako_ann/`** — IVF-PQ (Performance) and HNSW (Accuracy) search
- **`packages/kitako_normalizer/`** — rule-based Taglish query normalizer
- **`packages/kitako_ffi/`** — Flutter FFI plugin (native code)

### App services (`apps/lib/src/services/`)
- **`image_search_service.dart`** — central orchestrator: batch embedding (size 5),
  per-batch individual fallback on failure, partial-failure pause + retry/skip UI,
  lazy image loading (no eager thumbnail bytes)
- **`ann_search_service*.dart`** — ANN search wrapper (IO + web stub)
- **`face_service.dart`** — wraps the face pipeline; `main.dart` calls
  `tryAutoInitialize()` after the embedding pass (see §6 note on face indexing)
- **`image_loader_service.dart`** — `loadResizedForEmbedding()` decodes via
  `dart:ui.instantiateImageCodec(bytes, targetWidth:512, targetHeight:512)`
  (DCT scaling, avoids full-res 48 MB buffer); returns raw RGBA bytes
- **`embedding_service.dart`** (+ `_stub` for web), **`embedding_cache_service.dart`**,
  **`embedding_storage_service.dart`** — embedding + disk cache
- **`model_download_service.dart`** — model presence check + `copyModelsFromTmp()`
- **`camera_capture_service.dart`** — Take a Photo → save to gallery → index
- **`normalizer_service.dart`**, **`query_assist_service.dart`**,
  **`search_history_service.dart`**, **`crash_logger.dart`**

### App UI (`apps/lib/src/ui/screens/`)
- **`permission_screen.dart`**, **`eula_screen.dart`** — first-launch onboarding
- **`startup_screen.dart`** — indexing progress; amber retry/skip prompt on
  `IndexingPhase.embeddingPartialFailure`
- **`home_screen.dart`** — date-grouped gallery grid (2–6 columns, pinch to resize)
- **`search_screen.dart`**, **`results_screen.dart`**, **`details_screen.dart`**
- **`settings_screen.dart`** — appearance, search mode, top-results, history, model info
- **Unrouted on `master`:** `people_screen.dart`, `person_detail_screen.dart`,
  `alpha_test_screen.dart`. Nothing navigates to them (removed in `7695319`);
  `deployment` deletes them outright.

### Docs
- **`DESIGN.md`** — the app's visual design language (tokens, components, rules)
- **`docs/user-manual/`** — end-user manual. Edit `manual.src.html`, then run
  `python build.py` (or `--html-only`) to regenerate the HTML + PDF via headless Chrome.

### Thumbnail rendering rule (important)
All gallery/results grids use:
```dart
Image.file(File(image.path), fit: BoxFit.cover, cacheWidth: 256)
```
**Never specify both `cacheWidth` and `cacheHeight`.** Flutter decodes to an exact
square when both are given, stretching non-square photos before `BoxFit.cover`
can crop them. One dimension only → aspect-ratio-correct decode → clean crop.

### ONNX model output tensor names
- Image encoder output: **`image_embeds`** (shape `[batch, 768]`)
- Text encoder output: **`text_embeds`** (shape `[batch, 768]`)
- These are NOT `pooler_output`. Don't rename them.

### ONNX Runtime lifecycle rule
`OrtEnv.instance` is a **global singleton** — never call `OrtEnv.instance.release()`
when disposing individual sessions. Only dispose sessions and options. Releasing
the env breaks all subsequent model loading for the app's lifetime.

### Tokenizer alignment (verified 2026-04-22)
- No lowercasing (fast tokenizer ignores `do_lower_case`)
- No leading `▁` prepended to the first token
- No `.trim()` of input
- Right-padding: `[t0...tN, <eos>=1, <pad>=0, ...]` up to position 63
- `attention_mask` forced to all-1s (both Python and Dart side)
- EOS position found dynamically, not at hardcoded index -1

---

## 3. Model files and Git LFS

All `.onnx` files and `tokenizer.json` are tracked with **Git LFS**.
After cloning, run:

```bash
git lfs pull
```

If LFS is not installed: `git lfs install` first, then `git lfs pull`.

### Model locations (sizes from `git lfs ls-files -s`)
| Path | Purpose | Size |
|------|---------|------|
| `apps/assets/models/kitako_image_encoder_fp32.onnx` | Image encoder (app asset) | 372 MB |
| `apps/assets/models/kitako_text_encoder_int8.onnx` | Text encoder INT8 (app asset) | 286 MB |
| `apps/assets/models/tokenizer/tokenizer.json` | GemmaTokenizer vocab | 37 MB |
| `apps/assets/models/face/face_detector.onnx` | SCRFD-2.5G face detector | 2.5 MB |
| `apps/assets/models/face/face_embedder.onnx` | ArcFace MobileFaceNet | 14 MB |
| `models/kitako_image_encoder_fp32.onnx` | FP32 image encoder (desktop/tools) | 372 MB |
| `models/kitako_image_encoder_int8.onnx` | INT8 image encoder (desktop/tools) | 103 MB |
| `models/kitako_text_encoder_fp32.onnx` | FP32 text encoder (desktop/tools) | 1.1 GB |
| `models/kitako_text_encoder_int8.onnx` | INT8 text encoder (desktop/tools) | 286 MB |

> Note: `models/` and `apps/assets/models/*.onnx` appear in
> `.gitignore` but were force-added via LFS before the ignore rule was written.
> They ARE committed — `git lfs ls-files` confirms them. Do not re-add or re-ignore.

### Android model push (large FP32 models)
The `models/` FP32 models are too large to bundle as Flutter assets.
They are pushed to the device's `/data/local/tmp/` via a Gradle task that runs
automatically on every `flutter run`:

```bash
# Manual push if needed:
cd apps
./gradlew pushOnnxModels
```

The app's `ModelDownloadService.copyModelsFromTmp()` copies them to the app's
private storage on first launch.

---

## 4. Setup checklist for a new machine

```bash
# 1. Clone
git clone https://github.com/Emyol/KitaKo_Codebase.git
cd KitaKo_Codebase

# 2. Pull LFS objects (models, tokenizer)
git lfs install   # only needed once per machine
git lfs pull

# 3. Install Flutter dependencies
cd apps
flutter pub get

# 4. Install package dependencies
cd ../packages/kitako_embedding && dart pub get
cd ../kitako_core              && dart pub get
cd ../kitako_ann               && dart pub get
cd ../kitako_normalizer        && dart pub get

# 5. Android: verify a device is connected, then run
cd ../../apps
flutter run   # Gradle will auto-run pushOnnxModels
```

### Verify models arrived on device
```bash
adb shell ls -lh /data/local/tmp/*.onnx
```

### Check model presence in app
Open the app → Settings → scroll to "Models". Each model should show
"Ready". If any show "Missing", the app still runs but that feature is disabled.

---

## 5. Key architectural invariants — do not break

1. **`OrtEnv` is a singleton** — dispose sessions only, never the env.
2. **`cacheWidth` without `cacheHeight`** — all `Image.file` in gallery grids;
   specifying both forces a square decode that stretches non-square photos.
3. **Mock embeddings must not fall back silently** — `EmbeddingService` throws
   when ONNX backend is expected but not ready. Silent mock fallback produces
   garbage vectors that make search appear to work but return meaningless results.
4. **Face indexing is user-initiated only** — `startFaceIndexing()` must only be
   called from a user action (it was `PeopleScreen`, now unrouted). Do not add
   auto-calls in `main.dart` or `initState`; running face ONNX sessions
   concurrently with the embedding loop causes OOM (both use ~48 MB decode
   buffers + multi-hundred MB models). `main.dart` only loads the face models
   after the embedding pass finishes.
5. **Tokenizer pipeline** — see Section 2. Any change to tokenization must be
   validated against the Python reference (`external_test/query.py`, which
   lives outside this repo).
6. **ONNX output tensor names** — `image_embeds` / `text_embeds`. If you export
   a new model, verify these names before swapping.
