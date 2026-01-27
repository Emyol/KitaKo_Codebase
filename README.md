# KitaKo System

A Flutter-based semantic image retrieval system using SigLIP embeddings and HNSW approximate nearest neighbor search.

## Overview

KitaKo enables **natural language image search** with support for **Taglish** (Tagalog-English code-switching). Users can search their photo gallery using queries like "red dress" or "kumakain sa beach" and get semantically relevant results.

### Key Features

- 🔍 **Semantic Search** - Find images by meaning, not just keywords
- 🇵🇭 **Taglish Support** - Normalizes mixed Tagalog-English queries
- ⚡ **On-Device ML** - TensorFlow Lite inference, no server needed
- 🚀 **Fast ANN Search** - Native HNSW via FFI for millisecond retrieval

---

## Repository Structure

```
KitaKo_System/
├── apps/
│   └── kitako_app/          # Main Flutter application
├── packages/
│   ├── kitako_core/         # Shared models and utilities
│   ├── kitako_normalizer/   # Taglish text normalization
│   ├── kitako_embedding/    # SigLIP embedding service (TFLite)
│   ├── kitako_ann/          # ANN search service (HNSW)
│   └── kitako_ffi/          # Native FFI bindings (hnswlib)
├── assets/
│   ├── models/              # Source ML models
│   │   ├── image_encoder/   # SigLIP image encoder
│   │   ├── text_encoder/    # SigLIP text encoder
│   │   └── tokenizer/       # Tokenizer files
│   └── indexes/             # Prebuilt ANN indexes
└── tools/                   # CLI utilities
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

3. **Or run setup script**:
   ```powershell
   cd apps/kitako_app
   .\setup_tflite.ps1
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
dart run build_index.dart --images /path/to/images --output ../assets/index/
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
| ML Runtime | TensorFlow Lite |
| Embeddings | SigLIP (768-dim) |
| ANN Search | HNSW (hnswlib) |
| FFI | dart:ffi + ffigen |
| UI | Material Design 3 |

---

## License

Proprietary - All rights reserved.

---

**Last Updated**: January 27, 2026
