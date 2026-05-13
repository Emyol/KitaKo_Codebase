# KitaKo — Claude Migration Guide

This file is read automatically by Claude Code on every session. It covers the
branch layout, what changed vs. the base, where models live, and the exact
steps needed to get a fresh clone working on a new machine.

---

## 1. Active branch

**`v2-system-ric`** is the primary development branch. `master` is the older
baseline. Always work from `v2-system-ric` unless explicitly switching.

Other remote branches for reference:
| Branch | Purpose |
|--------|---------|
| `master` | Pre-ONNX TFLite baseline (largely superseded) |
| `feat/siglip1-aligned-embeddings` | Earlier SigLIP alignment work, merged into v2 |
| `feature/onnx-embedding-improvements` | ONNX iteration, merged into v2 |
| `origin/feat/face_recognition` | Face recognition prototype, merged into v2 |
| `origin/ann-algo` | IVF-PQ ANN experiments |

---

## 2. What `v2-system-ric` adds over `master`

### Embedding pipeline (ONNX, replaces TFLite)
- **`packages/kitako_embedding/`** — complete rewrite
  - `OnnxEmbeddingService` (`onnx_embedding_service.dart`) replaces TFLite service
  - `SiglipInference` (`siglip_inference.dart`) — ONNX Runtime image + text encoder
  - `GemmaTokenizer` (`gemma_tokenizer.dart`) — 256K-vocab SentencePiece BPE tokenizer
    aligned to HuggingFace `tokenizer.json` (no lowercasing, no leading ▁, right-pad)
  - `ImagePreprocessor` — added `preprocessRgbaAsync` / `preprocessRgbaInIsolate`
    for pre-decoded RGBA input (avoids re-decoding JPEG in isolate)
  - Face sub-package: `face_pipeline.dart`, `onnx_face_detector.dart` (SCRFD-2.5G),
    `onnx_face_embedder.dart` (ArcFace MobileFaceNet), `face_aligner.dart` (Umeyama),
    `face_dbscan.dart` (DBSCAN clustering)

- **`packages/kitako_core/`** — added face types
  - `face_constants.dart` — `kFaceEmbeddingDim=512`, `kFaceInputSize=112`,
    `kFaceDetectorInputSize=640`, `kFaceClusteringThreshold=0.45`, reference landmarks
  - `face_errors.dart`, `models/face_detection.dart` — Face/Person data models

### App services (`apps/lib/src/services/`)
- **`image_search_service.dart`** — central orchestrator: batch embedding (size 5),
  per-batch individual fallback on failure, partial-failure pause + retry/skip UI,
  lazy image loading (no eager thumbnail bytes), face indexing (user-initiated only)
- **`face_service.dart`** — wraps face pipeline; `tryAutoInitialize()` loads models
  silently; `startFaceIndexing()` is user-triggered from PeopleScreen
- **`image_loader_service.dart`** — added `loadResizedForEmbedding()`:
  decodes JPEG via `dart:ui.instantiateImageCodec(bytes, targetWidth:512, targetHeight:512)`
  (DCT scaling, avoids full-res 48 MB buffer); returns raw RGBA bytes
- **`embedding_service.dart`** — added `generateImageEmbeddingFromRgba(rgba, w, h)`
- **`embedding_service_stub.dart`** — web stub matching all method signatures
- **`embedding_cache_service.dart`**, **`embedding_storage_service.dart`** — disk cache
- **`model_download_service.dart`** — model presence check + download gate
- **`crash_logger.dart`** — on-disk crash log, wired into `main.dart`
- **`query_assist_service.dart`** — LLM query rewriting
- **`search_history_service.dart`** — persistent recent searches

### App UI
- **`home_screen.dart`** — gallery grid + inline similar-image results;
  all thumbnails use `Image.file(cacheWidth:256)` (no `cacheHeight` — preserves
  aspect ratio so `BoxFit.cover` crops rather than squishes)
- **`search_screen.dart`** — full text/image search UI
- **`results_screen.dart`** — search results grid with rank + score badges
- **`details_screen.dart`** — full image viewer with Find Similar
- **`people_screen.dart`** — face recognition gallery; "Find Faces" button triggers
  indexing manually (not on startup)
- **`person_detail_screen.dart`** — per-person photo grid + label + search-by-person
- **`alpha_test_screen.dart`** — developer test harness for embedding + search
- **`startup_screen.dart`** — indexing progress UI; shows amber retry/skip prompt
  on partial embedding failure (`IndexingPhase.embeddingPartialFailure`)
- **`settings_screen.dart`** — expanded settings including model info

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

All `.onnx`, `.tflite`, and `tokenizer.json` files are tracked with **Git LFS**.
After cloning, run:

```bash
git lfs pull
```

If LFS is not installed: `git lfs install` first, then `git lfs pull`.

### Model locations
| Path | Purpose | Size |
|------|---------|------|
| `apps/assets/models/kitako_image_encoder_fp32.onnx` | Image encoder (app asset) | ~190 MB |
| `apps/assets/models/kitako_text_encoder_int8.onnx` | Text encoder INT8 (app asset) | ~23 MB |
| `apps/assets/models/tokenizer/tokenizer.json` | GemmaTokenizer vocab | ~10 MB |
| `apps/assets/models/face/face_detector.onnx` | SCRFD-2.5G face detector | ~2.5 MB |
| `apps/assets/models/face/face_embedder.onnx` | ArcFace MobileFaceNet | ~13 MB |
| `models/kitako/kitako_image_encoder_fp32.onnx` | FP32 image encoder (desktop/tools) | ~380 MB |
| `models/kitako/kitako_text_encoder_fp32.onnx` | FP32 text encoder (desktop/tools) | ~90 MB |
| `models/kitako/kitako_text_encoder_int8.onnx` | INT8 text encoder (desktop/tools) | ~23 MB |

> Note: `models/kitako/` and `apps/assets/models/*.onnx` appear in
> `.gitignore` but were force-added via LFS before the ignore rule was written.
> They ARE committed — `git lfs ls-files` confirms them. Do not re-add or re-ignore.

### Android model push (large FP32 models)
The `models/kitako/` FP32 models are too large to bundle as Flutter assets.
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

## 4. Uncommitted working-tree changes (as of 2026-04-28)

These changes are on `v2-system-ric` but not yet committed. A new Claude on a
fresh clone will NOT see them unless they're committed or the original machine's
changes are pushed:

| File | Change |
|------|--------|
| `apps/lib/main.dart` | Removed `startFaceIndexing()` auto-call; face indexing is now user-initiated |
| `apps/lib/src/services/image_search_service.dart` | Batch size=5, per-batch fallback, pause/retry on failure, `loadResizedForEmbedding` pipeline, lazy loading |
| `apps/lib/src/services/embedding_service.dart` | Added `generateImageEmbeddingFromRgba` |
| `apps/lib/src/services/embedding_service_stub.dart` | Added `embedImageFromRgba` web stub |
| `apps/lib/src/services/image_loader_service.dart` | Added `loadResizedForEmbedding` (512×512 DCT pre-shrink via `dart:ui`) |
| `apps/lib/src/ui/screens/startup_screen.dart` | Amber retry/skip UI for `embeddingPartialFailure` phase |
| `apps/lib/src/ui/screens/home_screen.dart` | `Image.file(cacheWidth:256)` everywhere, no `cacheHeight` |
| `apps/lib/src/ui/screens/people_screen.dart` | `_indexingRequested` flag, "Find Faces" button, "No People Found" state |
| `apps/lib/src/ui/screens/person_detail_screen.dart` | `Image.file` for photo grid (no `cacheHeight`) |
| `apps/lib/src/ui/screens/results_screen.dart` | `Image.file` (no `cacheHeight`); all `withOpacity` → `withValues(alpha:)` |
| `apps/lib/src/ui/screens/search_screen.dart` | `Image.file` (no `cacheHeight`) in both thumbnail helpers |
| `apps/lib/src/ui/screens/alpha_test_screen.dart` | `Image.file` (no `cacheHeight`) in list tile |
| `packages/kitako_embedding/lib/src/image_preprocessor.dart` | Added `preprocessRgbaAsync` / `_preprocessRgbaInIsolate` |
| `packages/kitako_embedding/lib/src/onnx_embedding_service.dart` | Added `embedImageFromRgba` |
| `packages/kitako_embedding/pubspec.yaml` | Dependency updates |
| `models/kitako/kitako_text_encoder_int8.onnx` | Updated INT8 model (LFS pointer updated) |

**Action for a new Claude:** run `git status` immediately. If these files show as
modified, the changes were committed and you're up to date. If git status is
clean and the changes above are absent from the code, ask the user to push the
working-tree changes from the original machine first.

---

## 5. Setup checklist for a new machine

```bash
# 1. Clone
git clone <remote-url>
cd KitaKo_Codebase
git checkout v2-system-ric

# 2. Pull LFS objects (models, tokenizer)
git lfs install   # only needed once per machine
git lfs pull

# 3. Install Flutter dependencies
cd apps
flutter pub get

# 4. Install package dependencies
cd ../../packages/kitako_embedding && dart pub get
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
Open the app → Settings → scroll to "Model Info". All four models
(image encoder, text encoder, face detector, face embedder) should show
status "Ready". If any show "Missing", the app will still run but that
feature is disabled.

---

## 6. Key architectural invariants — do not break

1. **`OrtEnv` is a singleton** — dispose sessions only, never the env.
2. **`cacheWidth` without `cacheHeight`** — all `Image.file` in gallery grids;
   specifying both forces a square decode that stretches non-square photos.
3. **Mock embeddings must not fall back silently** — `EmbeddingService` throws
   when ONNX backend is expected but not ready. Silent mock fallback produces
   garbage vectors that make search appear to work but return meaningless results.
4. **Face indexing is user-initiated** — `startFaceIndexing()` is only called
   from `PeopleScreen._startFaceIndexing()`. Do not add auto-calls in `main.dart`
   or `initState`; loading face ONNX sessions concurrently with the embedding
   loop causes OOM (both use ~48 MB decode buffers + multi-hundred MB models).
5. **Tokenizer pipeline** — see Section 2. Any change to tokenization must be
   validated against the Python reference in `external_test/query.py`.
6. **ONNX output tensor names** — `image_embeds` / `text_embeds`. If you export
   a new model, verify these names before swapping.
