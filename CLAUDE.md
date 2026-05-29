# KitaKo — Claude Migration Guide

This file is read automatically by Claude Code on every session. It covers the
branch layout, what changed vs. the base, where models live, and the exact
steps needed to get a fresh clone working on a new machine.

---

## 1. Active branch

**`master`** is the primary development branch. Always work from `master`
unless explicitly switching.

Other remote branches for reference:
| Branch | Purpose |
|--------|---------|
| `v2-system-ric` | Former primary dev branch (superseded by `master`) |
| `feat/siglip1-aligned-embeddings` | Earlier SigLIP alignment work, merged in |
| `feature/onnx-embedding-improvements` | ONNX iteration, merged in |
| `origin/feat/face_recognition` | Face recognition prototype (now removed) |
| `origin/ann-algo` | IVF-PQ ANN experiments |

---

## 2. What the current system adds over the pre-ONNX TFLite baseline

### Embedding pipeline (ONNX, replaces TFLite)
- **`packages/kitako_embedding/`** — complete rewrite
  - `OnnxEmbeddingService` (`onnx_embedding_service.dart`) replaces TFLite service
  - `SiglipInference` (`siglip_inference.dart`) — ONNX Runtime image + text encoder
  - `GemmaTokenizer` (`gemma_tokenizer.dart`) — 256K-vocab SentencePiece BPE tokenizer
    aligned to HuggingFace `tokenizer.json` (no lowercasing, no leading ▁, right-pad)
  - `ImagePreprocessor` — added `preprocessRgbaAsync` / `preprocessRgbaInIsolate`
    for pre-decoded RGBA input (avoids re-decoding JPEG in isolate)

> **Removed (2026-05-29):** the face-recognition pipeline was deleted. The
> `packages/kitako_embedding/lib/src/face/` sub-package (`face_pipeline.dart`,
> `onnx_face_detector.dart`, `onnx_face_embedder.dart`, `face_aligner.dart`,
> `face_dbscan.dart`) and the `kitako_core` face types (`face_constants.dart`,
> `face_errors.dart`, `models/face_detection.dart`) no longer exist, and their
> exports were stripped from `kitako_embedding.dart` / `kitako_core.dart`.

### App services (`apps/lib/src/services/`)
- **`image_search_service.dart`** — central orchestrator: batch embedding (size 5),
  per-batch individual fallback on failure, partial-failure pause + retry/skip UI,
  lazy image loading (no eager thumbnail bytes)
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
- **`startup_screen.dart`** — indexing progress UI; shows amber retry/skip prompt
  on partial embedding failure (`IndexingPhase.embeddingPartialFailure`)
- **`settings_screen.dart`** — expanded settings including model info

> **Removed (2026-05-29):** `people_screen.dart`, `person_detail_screen.dart`
> (face-recognition UI) and `alpha_test_screen.dart` (developer embedding/search
> test harness) were deleted along with the rest of the face + alpha-test
> pipeline. The alpha-test-only `ImageSearchService` methods
> (`setForceBruteForce`, `annIndexStatus`, `setHnswEfSearch`, `retrainIvfpq`,
> `annSearchService` getter) and all `FaceService` wiring were removed too.

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
| `models/kitako_image_encoder_fp32.onnx` | FP32 image encoder (desktop/tools) | ~380 MB |
| `models/kitako_text_encoder_fp32.onnx` | FP32 text encoder (desktop/tools) | ~90 MB |
| `models/kitako_text_encoder_int8.onnx` | INT8 text encoder (desktop/tools) | ~23 MB |

> Note: `models/` and `apps/assets/models/*.onnx` appear in
> `.gitignore` but were force-added via LFS before the ignore rule was written.
> They ARE committed — `git lfs ls-files` confirms them. Do not re-add or re-ignore.

### Model delivery (production vs. dev)
- **Production (Play / packaged builds):** the two ONNX models now live in an
  **install-time Play Asset Delivery pack** at
  `apps/android/models_pack/src/main/assets/models/`, NOT in Flutter assets.
  See Section 7 for the full architecture. They are **not** in `apps/assets/models/`
  anymore (only the tokenizer remains there).
- **Dev (`flutter run`):** the `models/` files can still be ADB-pushed to
  `/data/local/tmp/` via `./gradlew pushOnnxModels` (run manually — the
  auto-push hook on `install*` was **removed** 2026-05-29). `ModelDownloadService`
  resolves from the app docs dir first, then `/data/local/tmp/`, then `<cwd>/models/`.

---

## 4. Uncommitted working-tree changes (as of 2026-04-28)

These changes are on `master` but not yet committed. A new Claude on a
fresh clone will NOT see them unless they're committed or the original machine's
changes are pushed:

| File | Change |
|------|--------|
| `apps/lib/main.dart` | Removed all `FaceService` wiring (field, deferred `tryAutoInitialize`, dispose) |
| `apps/lib/src/services/image_search_service.dart` | Batch size=5, per-batch fallback, pause/retry on failure, `loadResizedForEmbedding` pipeline, lazy loading; face + alpha-test methods removed |
| `apps/lib/src/services/embedding_service.dart` | Added `generateImageEmbeddingFromRgba` |
| `apps/lib/src/services/embedding_service_stub.dart` | Added `embedImageFromRgba` web stub |
| `apps/lib/src/services/image_loader_service.dart` | Added `loadResizedForEmbedding` (512×512 DCT pre-shrink via `dart:ui`) |
| `apps/lib/src/ui/screens/startup_screen.dart` | Amber retry/skip UI for `embeddingPartialFailure` phase |
| `apps/lib/src/ui/screens/home_screen.dart` | `Image.file(cacheWidth:256)` everywhere, no `cacheHeight` |
| `apps/lib/src/ui/screens/results_screen.dart` | `Image.file` (no `cacheHeight`); all `withOpacity` → `withValues(alpha:)` |
| `apps/lib/src/ui/screens/search_screen.dart` | `Image.file` (no `cacheHeight`) in both thumbnail helpers |
| `packages/kitako_embedding/lib/src/image_preprocessor.dart` | Added `preprocessRgbaAsync` / `_preprocessRgbaInIsolate` |
| `packages/kitako_embedding/lib/src/onnx_embedding_service.dart` | Added `embedImageFromRgba` |
| `packages/kitako_embedding/pubspec.yaml` | Dependency updates |
| `models/kitako_text_encoder_int8.onnx` | Updated INT8 model (LFS pointer updated) |

### Face + alpha-test removal (2026-05-29)
Deleted files:
- `apps/assets/models/face/` (`face_detector.onnx`, `face_embedder.onnx`)
- `apps/lib/src/services/face_service.dart`
- `apps/lib/src/ui/screens/people_screen.dart`, `person_detail_screen.dart`, `alpha_test_screen.dart`
- `packages/kitako_embedding/lib/src/face/` (whole sub-package)
- `packages/kitako_core/lib/src/{face_constants.dart,face_errors.dart,models/face_detection.dart}`

Edited files:
- `kitako_embedding.dart` / `kitako_core.dart` — face exports removed
- `apps/pubspec.yaml` — `assets/models/face/` asset entry removed

Kept intentionally: `setPreferredAlgorithm` / `preferHnsw` (used by Settings),
the `imageLoader` getter (used by search/details), and the underlying
`ANNSearchService.setHnswEfSearch` / `retrainIvfpq` library methods.

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
git checkout master

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
flutter run
# NOTE: models are no longer auto-pushed. For dev, push them once manually:
#   cd android && ./gradlew pushOnnxModels   (copies models/ → /data/local/tmp/)
# Packaged/release builds get models from the install-time asset pack (Section 7).
```

### Verify models arrived on device
```bash
adb shell ls -lh /data/local/tmp/*.onnx
```

### Check model presence in app
Open the app → Settings → scroll to "Model Info". Both models
(image encoder, text encoder) should show status "Ready". If either shows
"Missing", the app will still run but search is disabled.

---

## 6. Key architectural invariants — do not break

1. **`OrtEnv` is a singleton** — dispose sessions only, never the env.
2. **`cacheWidth` without `cacheHeight`** — all `Image.file` in gallery grids;
   specifying both forces a square decode that stretches non-square photos.
3. **Mock embeddings must not fall back silently** — `EmbeddingService` throws
   when ONNX backend is expected but not ready. Silent mock fallback produces
   garbage vectors that make search appear to work but return meaningless results.
4. **Face recognition is removed** — the face pipeline, models, and UI were
   deleted (see Section 4, 2026-05-29). Do not reintroduce `FaceService`,
   `PeopleScreen`, or the `apps/assets/models/face/` assets without revisiting
   the OOM constraints that originally gated it (face ONNX sessions loaded
   concurrently with the embedding loop exhausted memory on mid-range devices).
5. **Tokenizer pipeline** — see Section 2. Any change to tokenization must be
   validated against the Python reference in `external_test/query.py`.
6. **ONNX output tensor names** — `image_embeds` / `text_embeds`. If you export
   a new model, verify these names before swapping.
7. **Fully offline** — the app makes no runtime network calls and never
   downloads models (see Section 7). Don't add network model fetching;
   `query_assist_service` is an on-device dictionary, not a remote LLM.

---

## 7. Deployment (Google Play & alternatives)

Validated on-device 2026-05-29 (Samsung SM S9260, Android 16). The Flutter
project root is **`apps/`** (`apps/kitako_app/` is a stale build dir).

### App identity & signing
- **Application ID: `com.kitako.app`** — set as both `namespace` and
  `applicationId` in `apps/android/app/build.gradle.kts`; `MainActivity.kt` is in
  package `com.kitako.app`. **PERMANENT once published — never change it.**
- **Upload keystore:** `C:/Users/ricba/kitako-upload.jks` (alias `kitako`,
  PKCS12, valid to 2053, cert CN=KitaKo). Credentials in
  `apps/android/key.properties` (**gitignored**). Gradle auto-detects
  `key.properties` and signs release with it; falls back to the debug key if
  absent (so fresh clones/CI still build). **Back up the `.jks` + password.**

### Model delivery — install-time asset pack (Play size cap workaround)
The base AAB module is capped at ~200 MB download by Play; the FP32 image
encoder alone (~355 MB) exceeds that. So the two big models ship in an
**install-time Play Asset Delivery pack**:
- Module `:models_pack` — `apps/android/models_pack/` (`build.gradle.kts` with
  `deliveryType = install-time`), registered in `settings.gradle.kts` and via
  `assetPacks += listOf(":models_pack")` in the app gradle.
- Models: `apps/android/models_pack/src/main/assets/models/{kitako_image_encoder_fp32.onnx,kitako_text_encoder_int8.onnx}`.
- **First-launch extraction:** `MainActivity` exposes a `kitako_app/models`
  MethodChannel (`copyAsset` streams a pack asset via `AssetManager.open(...)` to
  a dest path). `ModelDownloadService.extractBundledModels()` (Android-only)
  copies models into the app docs dir, where `_resolvePath()` finds them first.
- install-time packs arrive **with the install** (present at first launch, no
  runtime network) — keeps the app fully offline (invariant #7). The tokenizer
  (~37 MB) stays a normal Flutter asset.

> Real model sizes (LFS): image FP32 ~355 MB, text INT8 ~273 MB — far larger
> than the old Section 3 table claimed. The "INT8" text encoder being ~273 MB is
> suspicious (FP32 text is ~90 MB) and may be mislabeled/non-quantized — worth
> verifying if download size matters.

### Build commands
```bash
cd apps
# Play upload artifact (signed AAB):
flutter build appbundle --release
#   → build/app/outputs/bundle/release/app-release.aab

# Sideload / non-Play self-contained APK (models baked in) — built from the AAB
# because a plain `flutter build apk` no longer includes the asset-pack models:
java -jar ../tools/bin/bundletool.jar build-apks \
  --bundle=build/app/outputs/bundle/release/app-release.aab \
  --mode=universal --output=app-universal.apks
```

### Local validation of the asset pack (before a Play round-trip)
`bundletool` jar at `tools/bin/bundletool.jar`. On Windows pass explicit
`--adb=`. `build-apks --connected-device --local-testing` then `install-apks`
reproduces Play's install-time delivery; confirm logs show
`ModelDownloadService: extracting … from asset pack` on a fresh install with an
empty `/data/local/tmp`.

### Publishing
- **Google Play** ($25 one-time, lifetime): create app → Play App Signing →
  internal testing → upload `app-release.aab` → Data Safety (all on-device, no
  data collected) + privacy policy URL + listing → promote to production.
- **Free alternatives** (distribute the universal APK): Amazon Appstore ($0),
  Samsung Galaxy Store ($0), GitHub Releases + IzzyOnDroid ($0), direct APK.

### Release artifacts & distribution
- Built artifacts live in **`dist/`** (`app-release.aab`, `KitaKo-v1.0.0.apk`,
  and the QR PNGs). **`dist/` is gitignored** — the large APK/AAB are distributed
  out-of-band (SourceForge), not committed to git.
- **QR codes:** `dist/kitako-download-qr.png` (APK download) and
  `dist/kitako-project-qr.png` (GitHub repo). Because `dist/` is ignored, copies
  for the README live in the tracked **`docs/images/`** dir and are embedded in
  the root `README.md` "Get KitaKo" section (just above "Repository Structure").
  If a QR's target URL changes, regenerate the PNG in `dist/` AND refresh the
  `docs/images/` copy so the README renders the current code.

### Known follow-ups (not blockers)
- First-launch full-gallery indexing is slow (~6688 imgs @ ~700 ms ≈ 75 min).
- Deployment work lives on the **`deployment`** branch (kept off `master`, which
  is the clean baseline). Commit deployment changes there, not on `master`.
