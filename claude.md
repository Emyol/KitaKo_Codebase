# KitaKo System — Codebase Guide

## Overview

KitaKo is a Flutter-based on-device image search and face recognition system. It uses SigLIP2 for text-to-image semantic search and SCRFD + ArcFace for face detection, embedding, and clustering.

## Project Structure

```
KitaKo_System/
├── apps/kitako_app/          # Flutter mobile app (Android/iOS)
├── packages/
│   ├── kitako_core/          # Shared constants, models, error types
│   ├── kitako_embedding/     # ONNX inference (SigLIP2 + face pipeline)
│   ├── kitako_ann/           # ANN search (HNSW, IVF-PQ, brute-force)
│   ├── kitako_ffi/           # Native C FFI bindings for ANN
│   └── kitako_normalizer/    # Text normalization for tokenizer
├── tools/                    # Python/Dart helper scripts
├── assets/                   # Models, tokenizer, test data (NOT in git)
└── docs/                     # Architecture & development docs
```

## Models (NOT in repository — must be obtained separately)

### SigLIP2 Models (Text-to-Image Search)

These ONNX models power the semantic image search feature.

| Model | File | Size | Source |
|-------|------|------|--------|
| SigLIP2 Vision Encoder | `siglip2_vision_model_fp32.onnx` | ~355 MB | Exported from `google/siglip2-base-patch16-256` |
| SigLIP2 Text Encoder | `siglip2_text_model_fp32.onnx` | ~1077 MB | Exported from `google/siglip2-base-patch16-256` |

**Quantized variants** (smaller, for mobile):
- `siglip2_vision_model_int8.onnx` (~90 MB)
- `siglip2_text_model_int8.onnx` (~270 MB)

**Location on device**: Pushed to device or downloaded via app UI to the app's internal storage.

### Face Recognition Models

| Model | File | Size | Source |
|-------|------|------|--------|
| SCRFD-2.5G (face detector) | `face_detector.onnx` | ~2.4 MB | `onnx-community/scrfd_2.5g_bnkps` on HuggingFace |
| ArcFace w600k_mbf (face embedder) | `face_embedder.onnx` | ~13 MB | `onnx-community/arcface_w600k_mbf` on HuggingFace |

**Download**: Run `python tools/python/download_face_models.py` to auto-download both from HuggingFace.

**Location on device**: Push to `/data/local/tmp/face_models/` via ADB — the app auto-copies them to internal storage on first launch.

```bash
adb push assets/face_models/face_detector.onnx /data/local/tmp/face_models/
adb push assets/face_models/face_embedder.onnx /data/local/tmp/face_models/
```

### Tokenizer Files

The SigLIP2 tokenizer config files are in `assets/models/tokenizer/`. Small JSON/text files are tracked in git. The large `tokenizer.json` (~35 MB) is gitignored and must be obtained from the HuggingFace model repo.

## Test Images (NOT in repository)

Test images are stored locally in `assets/test_images/taglish_test_images/` (~11,329 JPG files). These are pushed to the device at `/data/local/tmp/test_images/` for testing.

```bash
adb push assets/test_images/taglish_test_images/ /data/local/tmp/test_images/
adb shell chmod -R 755 /data/local/tmp/test_images/
```

The app's `image_loader_service.dart` is currently configured to scan `/data/local/tmp/test_images/` instead of the device gallery. To switch back to gallery mode, restore `photo_manager` usage in that file.

## Key Technical Details

### Face Recognition Pipeline

1. **Detection**: SCRFD-2.5G — input `[1, 3, 640, 640]` NCHW Float32, letterbox-resized
2. **Alignment**: Umeyama similarity transform to 112×112 canonical ArcFace template
3. **Embedding**: ArcFace w600k_mbf — 512-dim L2-normalized embeddings
4. **Clustering**: DBSCAN with cosine distance, eps=0.45, minPoints=2

### SigLIP2 Inference

- Vision: `[1, 3, 256, 256]` NCHW Float32 → 768-dim embedding
- Text: Tokenized input → 768-dim embedding
- Search: Cosine similarity between text and image embeddings

### ANN Search Algorithms

- **HNSW**: Default, best accuracy-speed tradeoff
- **IVF-PQ**: Lower memory, uses product quantization
- **Brute-force**: Exact search, reference implementation

## Build & Run

```bash
cd apps/kitako_app
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## What's Git-Ignored

The following are excluded from the repository (see `.gitignore`):
- All `.onnx` model files (too large)
- All `.tflite` model files
- `assets/face_models/` — face recognition ONNX models
- `assets/test_images/` — test image dataset
- `assets/indexes/` — ANN index files (generated at runtime)
- `dataset/images/` — raw dataset images
- `tools/onnx_models_*/` — intermediate model exports
- `tools/xenova_models/` — Xenova model cache
- `apps/kitako_app/blobs/` — binary cache
- Build outputs (`**/build/`, `**/.dart_tool/`)
- Native binaries (`*.dll`, `*.so`, `*.dylib`)
