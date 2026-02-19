# KitaKo System

A Flutter-based semantic image retrieval system using SigLIP embeddings and HNSW approximate nearest neighbor search.

## Overview

KitaKo enables **natural language image search** with support for **Taglish** (Tagalog-English code-switching). Users can search their photo gallery using queries like "red dress" or "kumakain sa beach" and get semantically relevant results.

### Key Features

- 🔍 **Semantic Search** - Find images by meaning, not just keywords
- 🇵🇭 **Taglish Support** - Normalizes mixed Tagalog-English queries
- ⚡ **On-Device ML** - ONNX Runtime inference, no server needed
- 🚀 **Fast ANN Search** - IVF-PQ (pure Dart) + native HNSW via FFI
- 📱 **Multi-Model** - Toggle between SigLIP-1, SigLIP-2, and fine-tuned variants at runtime

---

## System Status Report

> **Report Date:** February 15, 2026

### Current Capabilities

#### 1. Taglish Text Normalization ✅
The system includes a fully functional 10-step Taglish normalization pipeline:
- **120+ abbreviation expansions** — Filipino text speak mapped to formal words (e.g., `aq` → `ako`, `bkt` → `bakit`, `kc` → `kasi`)
- **"nag-" verb extraction** — Handles Taglish verb construction (e.g., `nagshopping` → `shopping`) across 73 English verbs
- **Reduplication preservation** — Recognizes 29 valid Tagalog reduplication pairs (e.g., `halo halo`, `dahan dahan`, `sari sari`)
- **Character normalization** — Collapse repeated characters, normalize whitespace, strip extraneous punctuation

#### 2. SigLIP Embedding Generation ✅
On-device ML inference using ONNX Runtime (768-dimensional embeddings):

| Model Version | Vocab Size | Status | Deployment |
|---------------|-----------|--------|------------|
| SigLIP-1 Quantized | 32,000 | Auto-downloadable (~210 MB from HuggingFace) | Automatic |
| SigLIP-1 Aligned | 32,000 | Available (~775 MB) | Manual (ADB push) |
| SigLIP-2 FP32 | 256,000 | Available (~1.5 GB) | Manual (ADB push) |
| Fine-tuned SigLIP | 256,000 | Available (~1.4 GB) | Manual (ADB push) |

- **Cascading model initialization** — Tries models in priority order (Fine-tuned → Aligned → SigLIP-2 → SigLIP-1 → Mock fallback)
- **Runtime model switching** — Switch between model versions without app restart
- **Image preprocessing** — Decode, resize to 224×224, normalize to [-1, 1], NHWC→NCHW conversion
- **Text tokenization** — BPE/SentencePiece tokenizer supporting both 32K and 256K vocabularies
- **LRU embedding cache** — 100-entry cache for repeated queries

#### 3. Approximate Nearest Neighbor Search ✅
Two search algorithms available:

| Algorithm | Implementation | Best For |
|-----------|---------------|----------|
| **IVF-PQ** | Pure Dart | Primary search (>100 images); no native dependencies |
| **HNSW** | Native C++ (via FFI) | High-performance search; requires compiled native library |
| **Brute-Force** | Pure Dart | Automatic fallback for ≤100 images; exact results |

IVF-PQ defaults for 768-dim SigLIP embeddings: 32 clusters, 48 subquantizers, 256 centroids/SQ, 8 probes.

#### 4. Device Photo Indexing ✅
- Indexes up to **1,000 device photos** automatically on app launch
- Parallel batch processing (10 images concurrently) using thumbnails for speed
- Re-indexes after model switch
- Reactive state updates via Dart streams

#### 5. Search Modes ✅
- **Text-to-Image** — Type a natural language query (English, Tagalog, or Taglish)
- **Image-to-Image** — Select a photo and find visually similar images via `image_picker`

#### 6. User Interface ✅
- **Startup Screen** — Animated splash with fade-in logo
- **Home Screen** — 3-column gallery grid of indexed images with search bar
- **Search Screen** — Text input + image picker, normalized query display, results grid with rank badges
- **Results Screen** — 2-column results with query header, result count, and search timing
- **Details Screen** — Full-size image viewer with pinch zoom, metadata panel (name, path, size, dimensions, dates), share functionality, prev/next navigation
- **Settings Screen** — Dark/light theme toggle
- **Model Download Gate** — First-run model download UI with progress bar and "Demo Mode" skip option
- **Alpha Test Screen** — IVF-PQ parameter tuning and accuracy benchmarking tools

#### 7. Model Management ✅
- **Auto-download** SigLIP-1 quantized models from HuggingFace on first launch
- **ADB push support** — Detects models pushed to `/data/local/tmp/` on Android
- **Size-based integrity verification** (±5% tolerance)
- **Cache management** — Clear downloaded models, report cache size

---

### Known Limitations

#### Embedding Quality Issue ⚠️
The most critical known issue: **search results may be semantically irrelevant**. The publicly available Xenova ONNX model exports are missing projection layers, which means vision and text embeddings exist in **different vector spaces**. This results in near-random cosine similarities (~2.0 L2 distance for normalized vectors). A corrected export script exists at `tools/python/export/export_siglip_with_projection.py` but has not been run to produce fixed models.

#### Incomplete UI Features
| Feature | Status |
|---------|--------|
| Similarity score display | Shows mock percentages (hardcoded), not real scores |
| Image deletion | UI dialog exists but does not delete |
| Open containing folder | Stub only (shows snackbar) |
| Grid/list view toggle | Button present but non-functional |
| Settings beyond dark mode | Toggle switches are visual stubs |

#### Platform Support

| Platform | Gallery Access | ML Inference | ANN Search | Overall |
|----------|---------------|-------------|------------|---------|
| **Android** | ✅ Real photos | ✅ ONNX Runtime | ✅ IVF-PQ | **Full support** |
| **iOS** | ✅ Real photos | ✅ ONNX Runtime | ✅ IVF-PQ | **Full support** |
| **Windows** | ⚠️ Mock images | ⚠️ Depends on native libs | ✅ IVF-PQ | **Partial** |
| **macOS/Linux** | ⚠️ Mock images | ⚠️ Depends on native libs | ✅ IVF-PQ | **Partial** |
| **Web** | ❌ Mock only | ❌ Stubbed out | ❌ Stubbed out | **Mock mode only** |

---

### Use Cases

#### Primary Use Case: Taglish Photo Search
A Filipino user searches their phone gallery using natural mixed-language queries:
- `"kumakain sa beach"` (eating at the beach)
- `"nagshopping kami"` (we went shopping)
- `"red dress sa party"` (red dress at a party)
- `"aso sa park"` (dog at the park)

The normalizer converts informal abbreviations to searchable text, the embedding model encodes the query into a vector, and the ANN index returns the most visually relevant photos from the device gallery.

#### Secondary Use Case: Image-to-Image Similarity
A user selects a photo and finds similar-looking images within their gallery (visual similarity search using the vision encoder to embed both the query image and gallery images).

#### Research / Alpha Testing Use Case
Developers and researchers can:
- Benchmark IVF-PQ vs brute-force recall at various parameter settings
- Tune ANN parameters (numProbes, clusters, subquantizers) in real-time
- Compare embedding quality across SigLIP-1, SigLIP-2, and fine-tuned models
- Test normalization quality on Taglish inputs via the debug/alpha test screens

#### Offline / Privacy Use Case
All inference runs on-device — no images or queries are sent to any server. This makes KitaKo suitable for privacy-sensitive photo collections where cloud-based search is not acceptable.

---

### Component Status Summary

| Component | Package | Status | Notes |
|-----------|---------|--------|-------|
| Taglish Normalizer | `kitako_normalizer` | ✅ Working | 120+ mappings, 73 verbs, 29 reduplication pairs |
| SigLIP Tokenizer | `kitako_embedding` | ✅ Working | 32K and 256K vocab support |
| Image Preprocessor | `kitako_embedding` | ✅ Working | Resize + normalize + format conversion |
| ONNX Inference | `kitako_embedding` | ⚠️ Partial | Runs but needs fixed projection-layer models |
| IVF-PQ Search | `kitako_ann` | ✅ Working | Pure Dart, tested, benchmarkable |
| HNSW Search | `kitako_ann` + `kitako_ffi` | ✅ Available | Native FFI; not used by app (IVF-PQ preferred) |
| Brute-Force Search | `kitako_ann` | ✅ Working | Exact NN; auto-selected for ≤100 images |
| Model Download | App services | ✅ Working | Auto-download SigLIP-1; manual setup for others |
| Photo Gallery | App services | ✅ Working | Android/iOS real photos; desktop/web mock |
| Search UI | App UI | ✅ Working | Text + image search with results grid |
| Image Viewer | App UI | ✅ Working | Full-size zoom, metadata, share, navigation |
| Theme System | App UI | ✅ Working | Dark/light toggle with Material 3 |
| Shared Types | `kitako_core` | ✅ Working | EmbeddingVector, AnnResult, error hierarchy |

---

## Repository Structure

```
KitaKo_System/
├── apps/
│   └── kitako_app/              # Main Flutter application
│       ├── lib/
│       │   ├── main.dart        # App entry point
│       │   └── src/
│       │       ├── bootstrap/   # App initialization
│       │       ├── models/      # View models / data classes
│       │       ├── services/    # Business logic services
│       │       ├── state/       # State management (providers, controllers)
│       │       ├── ui/
│       │       │   ├── screens/ # All app screens
│       │       │   ├── theme/   # Theming (colors, dark mode)
│       │       │   └── widgets/ # Reusable UI components
│       │       └── utils/       # Logging, exceptions, perf
│       ├── assets/              # Runtime-bundled assets only
│       └── test/
├── packages/
│   ├── kitako_core/             # Shared types (EmbeddingVector, AnnResult, errors)
│   ├── kitako_normalizer/       # Taglish text normalization
│   ├── kitako_embedding/        # SigLIP inference (TFLite + ONNX)
│   ├── kitako_ann/              # ANN search (HNSW + IVF-PQ)
│   └── kitako_ffi/              # Native FFI bindings (hnswlib C++)
├── assets/                      # Shared model/data files (gitignored large files)
│   ├── models/
│   │   ├── tokenizer/
│   │   ├── image_encoder/
│   │   ├── text_encoder/
│   │   └── onnx/               # ONNX model iterations (gitignored)
│   ├── metadata/
│   └── test_images/             # Test image sets (gitignored)
├── tools/
│   ├── dart/                    # Dart CLI tools (index builder, tokenizer checks)
│   └── python/
│       ├── export/              # Model export scripts
│       ├── test/                # Model validation/testing
│       └── utils/               # Conversion, quantization, inspection
├── docs/
│   ├── architecture/            # System design, handoff notes, requirements
│   ├── guides/                  # SigLIP setup, model toggle instructions
│   └── development/             # App setup, mobile tips, screen flow
└── dataset/                     # Training/test datasets (gitignored)
```

---

## Quick Start

### Prerequisites

- **Flutter SDK** ≥ 3.10.4
- **Dart SDK** ≥ 3.10.4
- **Visual Studio 2022** with C++ workload (Windows)
- **Xcode** (macOS/iOS)
- **Android Studio** with NDK (Android)

### 1. Clone and Setup

```bash
git clone <repo-url>
cd KitaKo_System
```

### 2. Install Dependencies

```bash
cd apps/kitako_app
flutter pub get
```

### 3. Platform-Specific Setup

#### Windows (TFLite DLL Required)

The embedding service requires the TensorFlow Lite C library:

1. **Download** from [tflite-flutter releases](https://github.com/am15h/tflite_flutter_plugin/releases)
   - Get `libtensorflowlite_c-win.dll` for your architecture (x64)

2. **Place in blobs folder**:
   ```
   apps/kitako_app/blobs/libtensorflowlite_c-win.dll
   ```

#### Android

Native libraries are bundled automatically. Just run:
```bash
flutter run -d android
```

#### iOS / macOS

Native libraries are bundled automatically via CocoaPods:
```bash
cd ios && pod install && cd ..
flutter run -d ios
```

### 4. Run the App

```bash
# Windows
flutter run -d windows

# Android
flutter run -d android

# iOS (macOS only)
flutter run -d ios

# Web (mock mode only - no FFI)
flutter run -d chrome
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter UI Layer                            │
│              (SearchScreen, GalleryView, Results)                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ImageSearchService                           │
│                (Orchestrates search pipeline)                    │
└─────────────────────────────────────────────────────────────────┘
        │                     │                      │
        ▼                     ▼                      ▼
┌───────────────┐   ┌─────────────────┐   ┌─────────────────────┐
│ TaglishNorm   │   │ EmbeddingService│   │   ANNSearchService  │
│ (Pure Dart)   │   │ (TFLite + Dart) │   │   (HNSW + Dart)     │
└───────────────┘   └─────────────────┘   └─────────────────────┘
                            │                        │
                            ▼                        ▼
                    ┌───────────────┐        ┌─────────────┐
                    │  TFLite C API │        │  kitako_ffi │
                    │   (Native)    │        │  (hnswlib)  │
                    └───────────────┘        └─────────────┘
```

### Package Dependencies

```
kitako_app
├── kitako_core          # Shared types
├── kitako_normalizer    # Text normalization
├── kitako_embedding     # ML embeddings
│   └── tflite_flutter   # TFLite runtime
└── kitako_ann           # ANN search
    └── kitako_ffi       # Native HNSW
```

---

## Packages

### kitako_core
Shared data models and utilities used across all packages.

### kitako_normalizer
Taglish text normalizer that handles:
- Informal abbreviations (`aq` → `ako`, `kc` → `kasi`)
- Word concatenation (`nagshopping` → `nag shopping`)
- Common misspellings and slang

```dart
final normalizer = TaglishNormalizer();
final result = normalizer.normalize("gutom n aq kc d p kumain");
// Output: "gutom na ako kasi di pa kumain"
```

### kitako_embedding
SigLIP-based embedding service using TensorFlow Lite:
- 768-dimensional embeddings
- Text and image encoding
- L2 normalized outputs

```dart
final service = KitakoEmbeddingService();
await service.initialize(
  imageModelPath: 'assets/model/image_encoder/...',
  textModelPath: 'assets/model/text_encoder/...',
  tokenizerPath: 'assets/tokenizer/tokenizer.json',
);

final textEmbed = service.embedText("red dress");
final imageEmbed = service.embedImage(imageBytes);
```

### kitako_ann
Approximate Nearest Neighbor search using HNSW:
- Sub-millisecond search on 100K+ vectors
- Configurable search parameters (ef, k)
- Index persistence

```dart
final ann = AnnSearchService();
await ann.initialize(indexPath: 'path/to/index.bin');

final results = await ann.search(queryVector, k: 10);
```

### kitako_ffi
Native FFI bindings for hnswlib:
- C++ HNSW implementation
- Cross-platform support (Windows, macOS, Linux, Android, iOS)
- Dart FFI integration

---

## Assets

### Models (Required)

| File | Location | Description |
|------|----------|-------------|
| `kitako_image_encoder_int8.tflite` | `assets/model/image_encoder/` | SigLIP image encoder (quantized) |
| `kitako_text_encoder_dynamic.tflite` | `assets/model/text_encoder/` | SigLIP text encoder |
| `tokenizer.json` | `assets/tokenizer/` | SigLIP tokenizer vocab |

### Index (Optional)

| File | Location | Description |
|------|----------|-------------|
| `ann_index.bin` | `assets/index/` | Prebuilt HNSW index |
| `ann_index.meta.json` | `assets/index/` | Index metadata (ID mappings) |

### Native Libraries

| Platform | Library | Setup |
|----------|---------|-------|
| Windows | `libtensorflowlite_c-win.dll` | Manual download to `blobs/` |
| Android | Bundled in AAR | Automatic |
| iOS | Bundled via CocoaPods | Automatic |
| macOS | `.dylib` | Automatic or manual |
| Linux | `.so` | Manual download |
| **Web** | ❌ Not supported | Uses mock fallback |

---

## Fallback Behavior

The app gracefully degrades when native libraries are unavailable:

| Scenario | Behavior |
|----------|----------|
| TFLite DLL missing | Mock embeddings (random vectors) |
| HNSW index missing | Brute-force search on in-memory vectors |
| Web platform | Full mock mode (UI testing only) |

Debug logs indicate the active mode:
```
EmbeddingService: Running in MOCK mode
ANNSearchService: Using brute-force fallback
```

---

## Building an Index

To index your own images:

```bash
cd tools
dart run dart/build_index.dart --images /path/to/images --output ../assets/indexes/
```

This generates:
- `ann_index.bin` - HNSW index file
- `ann_index.meta.json` - Image ID to path mappings

---

## Testing

### Run Unit Tests

```bash
# All packages
flutter test

# Specific package
cd packages/kitako_normalizer
flutter test
```

### Test Search Manually

1. Run the app
2. Enter queries:
   - `"dog"` or `"cat"` → See results
   - `"nagshopping aq"` → See Taglish normalization
   - Random text → See "No results" fallback

---

## Troubleshooting

### Windows: LNK1168 File Lock Error

```
LINK : fatal error LNK1168: cannot open ...kitako_app.exe for writing
```

**Fix**: Close VS Code, delete `build/` folder, reopen and rebuild:
```powershell
Remove-Item -Recurse -Force apps/kitako_app/build
flutter clean
flutter run -d windows
```

### Windows: TFLite Not Loading

```
EmbeddingService: Failed to initialize TFLite
```

**Fix**: Ensure `libtensorflowlite_c-win.dll` is in `blobs/` folder.

### Web: FFI Not Supported

Web builds run in **mock mode** because `dart:ffi` doesn't work in browsers. This is expected behavior - use native platforms for real inference.

---

## Development

### Adding a New Package

```bash
cd packages
flutter create --template=package kitako_newpackage
```

Update `apps/kitako_app/pubspec.yaml`:
```yaml
dependencies:
  kitako_newpackage:
    path: ../../packages/kitako_newpackage
```

### Code Style

```bash
dart format .
dart analyze
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x |
| Language | Dart 3.x |
| ML Runtime | ONNX Runtime (primary), TensorFlow Lite (legacy) |
| Embeddings | SigLIP / SigLIP-2 (768-dim) |
| ANN Search | IVF-PQ (pure Dart, primary), HNSW (native C++ via FFI) |
| FFI | dart:ffi + ffigen |
| UI | Material Design 3 |
| Gallery | photo_manager |
| Tokenizer | BPE/SentencePiece (HuggingFace format) |

---

## License

Proprietary - All rights reserved.

---

**Last Updated**: February 15, 2026
