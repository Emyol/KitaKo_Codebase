# KitaKo

A Flutter-based semantic image retrieval system using SigLIP-2 embeddings and IVF-PQ approximate nearest neighbor search — running fully on-device via ONNX Runtime.

## Overview

KitaKo enables **natural language image search** with support for **Taglish** (Tagalog-English code-switching). Users can search their device photo gallery using queries like `"red dress"` or `"kumakain sa beach"` and get semantically relevant results without any server or internet connection.

### Key Features

- **Semantic Search** — Find images by meaning, not keywords
- **Taglish Support** — Normalizes mixed Tagalog-English queries
- **On-Device ML** — ONNX Runtime inference, fully offline
- **Fast ANN Search** — IVF-PQ index for millisecond retrieval
- **Image-to-Image Search** — Find similar photos from camera or gallery
- **Resizable Gallery** — Pinch-to-zoom column count, persisted across sessions
- **Progressive Loading** — Gallery renders immediately; embedding runs in background

---

## Get KitaKo

Scan with your phone's camera:

<table>
  <tr>
    <td align="center">
      <img src="docs/images/kitako-download-qr.png" alt="Download KitaKo APK" width="180" /><br/>
      <strong>Download the app</strong><br/>
      <sub>KitaKo v1.0.0 · Android APK</sub>
    </td>
    <td align="center">
      <img src="docs/images/kitako-project-qr.png" alt="KitaKo project repository" width="180" /><br/>
      <strong>Project repository</strong><br/>
      <sub>Source code on GitHub</sub>
    </td>
  </tr>
</table>

---

## Repository Structure

```
KitaKo_Codebase/
├── apps/                        # Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   └── src/
│   │       ├── services/        # Business logic & ML orchestration
│   │       ├── ui/screens/      # App screens
│   │       └── models/
│   ├── assets/
│   │   └── models/              # Bundled ONNX models + tokenizer
│   │       ├── kitako_text_encoder_int8.onnx
│   │       ├── tokenizer/
│   │       └── face/            # Face detector + embedder
│   └── android/ / ios/
├── packages/
│   ├── kitako_core/             # Shared types and constants
│   ├── kitako_normalizer/       # Taglish text normalization
│   ├── kitako_embedding/        # SigLIP-2 ONNX inference + GemmaTokenizer
│   └── kitako_ann/              # IVF-PQ ANN search
├── models/                      # Full-size FP32 models (pushed to device via Gradle)
└── tools/                       # CLI utilities and inspection scripts
```

---

## Quick Start

### Prerequisites

- **Flutter SDK** ≥ 3.19
- **Dart SDK** ≥ 3.3
- **Git LFS** (models are LFS-tracked)
- **Android Studio** with NDK (Android target)
- **Xcode** (iOS target)

### 1. Clone and pull models

```bash
git clone <repo-url>
cd KitaKo_Codebase
git checkout master

# Pull LFS objects (ONNX models, tokenizer.json)
git lfs install   # only needed once per machine
git lfs pull
```

### 2. Install dependencies

```bash
cd apps
flutter pub get

cd ../packages/kitako_embedding && dart pub get
cd ../kitako_core               && dart pub get
cd ../kitako_ann                && dart pub get
cd ../kitako_normalizer         && dart pub get
```

### 3. Run (Android)

```bash
cd apps
flutter run   # Gradle auto-runs pushOnnxModels to push FP32 models to /data/local/tmp/
```

The Gradle task `pushOnnxModels` copies the large FP32 image encoder (~380 MB) to the device before launch. The app then copies it to private storage on first run.

### 4. Verify models on device

```bash
adb shell ls -lh /data/local/tmp/*.onnx
```

Open the app → **Settings → Model Info** — all four models should show **Ready**.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                        Flutter UI                         │
│   HomeScreen · SearchScreen · ResultsScreen · Details    │
└──────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│                   ImageSearchService                      │
│          (Orchestrates embedding + ANN pipeline)         │
└──────────────────────────────────────────────────────────┘
        │               │                │
        ▼               ▼                ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────────────┐
│ Normalizer   │ │  Embedding  │ │    ANNSearchService   │
│ (Taglish)    │ │  Service    │ │    (IVF-PQ index)     │
└──────────────┘ └─────────────┘ └──────────────────────┘
                        │
                        ▼
               ┌─────────────────┐
               │  ONNX Runtime   │
               │ SigLIP-2 image  │
               │ + text encoder  │
               └─────────────────┘
```

### Package Dependencies

```
apps
├── kitako_core          # Shared types
├── kitako_normalizer    # Taglish normalization
├── kitako_embedding     # ONNX inference (SigLIP-2, GemmaTokenizer)
└── kitako_ann           # IVF-PQ ANN search
```

---

## Packages

### kitako_core
Shared data models and constants used across all packages. Includes `ImageItem`, `SearchResult`, and face-related types (`FaceDetection`, `Person`).

### kitako_normalizer
Taglish text normalizer — handles informal abbreviations, word concatenation, common slang:

```dart
final normalizer = TaglishNormalizer();
final result = normalizer.normalize("gutom n aq kc d p kumain");
// "gutom na ako kasi di pa kumain"
```

### kitako_embedding
SigLIP-2 ONNX inference with GemmaTokenizer (256K vocab):
- 768-dimensional L2-normalized embeddings
- Text encoder: `kitako_text_encoder_int8.onnx` (~23 MB, INT8)
- Image encoder: `kitako_image_encoder_fp32.onnx` (~380 MB FP32, pushed via Gradle)
- Input images pre-shrunk to 512×512 via `dart:ui` DCT scaling before embedding

```dart
final service = OnnxEmbeddingService();
await service.initialize(imageModelPath: '...', textModelPath: '...', tokenizerPath: '...');

final textEmbed = await service.embedText("red dress");
final imageEmbed = await service.embedImageFromRgba(rgbaBytes, width, height);
```

### kitako_ann
IVF-PQ approximate nearest neighbor search:
- Sub-millisecond search on large galleries
- Configurable accuracy/speed tradeoff
- Index persisted to app storage

---

## Models

All `.onnx` and `tokenizer.json` files are tracked with **Git LFS**.

| Path | Purpose | Size |
|------|---------|------|
| `apps/assets/models/kitako_text_encoder_int8.onnx` | Text encoder INT8 (bundled) | ~23 MB |
| `apps/assets/models/tokenizer/tokenizer.json` | GemmaTokenizer vocab | ~10 MB |
| `apps/assets/models/face/face_detector.onnx` | SCRFD-2.5G face detector | ~2.5 MB |
| `apps/assets/models/face/face_embedder.onnx` | ArcFace MobileFaceNet | ~13 MB |
| `models/kitako_image_encoder_fp32.onnx` | Image encoder FP32 (device push) | ~380 MB |
| `models/kitako_text_encoder_fp32.onnx` | Text encoder FP32 (desktop tools) | ~90 MB |

> The FP32 image encoder is too large to bundle as a Flutter asset. It is pushed to `/data/local/tmp/` on the Android device via `./gradlew pushOnnxModels`, then copied to app private storage on first launch by `ModelDownloadService`.

---

## App Flow

1. **PermissionScreen** — requests storage/camera permissions (shown once)
2. **EulaScreen** — EULA acceptance gate (shown once)
3. **StartupScreen** — loads models and warms the embedding cache; navigates to home as soon as gallery is loading (embedding continues in background)
4. **HomeScreen** — photo grid with pinch-to-zoom column count (2–6), inline indexing progress
5. **SearchScreen** — text or image query input
6. **ResultsScreen** — ranked results with similarity scores
7. **DetailsScreen** — full image view with "Find Similar"

---

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android | Supported |
| iOS | Supported |
| Web / Windows / macOS / Linux | Not supported (removed) |

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x |
| Language | Dart 3.x |
| ML Runtime | ONNX Runtime (onnxruntime_flutter) |
| Embeddings | SigLIP-2 (768-dim, GemmaTokenizer) |
| ANN Search | IVF-PQ (pure Dart) |
| UI | Material Design 3 |

---

## License

Proprietary — All rights reserved.

---

**Last Updated**: May 2026
