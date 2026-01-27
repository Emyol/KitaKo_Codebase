# KitaKo System - Software Requirements & Dependencies

> **Document Purpose**: This README documents all software dependencies, tools, and requirements for the KitaKo multimodal image retrieval system. Intended for the Software Requirements section of the methodology documentation.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Development Environment](#development-environment)
3. [Dart/Flutter Dependencies](#dartflutter-dependencies)
4. [Native Dependencies](#native-dependencies)
5. [Machine Learning Models](#machine-learning-models)
6. [Build Tools](#build-tools)
7. [Platform-Specific Requirements](#platform-specific-requirements)
8. [Dependency Matrix](#dependency-matrix)

---

## System Overview

**KitaKo** is a cross-platform Flutter application for multimodal image retrieval using text queries. The system supports Filipino/Tagalog/English (Taglish) natural language queries through custom text normalization and semantic embedding-based search.

### Architecture Components

| Component | Package | Purpose |
|-----------|---------|---------|
| Main Application | `kitako_app` | Flutter UI and service orchestration |
| Core Library | `kitako_core` | Shared types and utilities |
| Text Normalizer | `kitako_normalizer` | Taglish text preprocessing |
| Embedding Service | `kitako_embedding` | TFLite-based text/image encoding |
| ANN Search | `kitako_ann` | HNSW approximate nearest neighbor search |
| Native FFI | `kitako_ffi` | C/C++ bindings for HNSW library |

---

## Development Environment

### Required Software

| Software | Minimum Version | Purpose |
|----------|-----------------|---------|
| **Flutter SDK** | 3.3.0+ | Cross-platform UI framework |
| **Dart SDK** | 3.10.4+ | Programming language |
| **CMake** | 3.10+ | Native code compilation |
| **C++ Compiler** | C++14 capable | HNSW native library |

### Recommended IDE

| IDE | Extensions |
|-----|------------|
| Visual Studio Code | Dart, Flutter, C/C++ |
| Android Studio | Flutter, Dart plugins |

---

## Dart/Flutter Dependencies

### Main Application (`kitako_app`)

```yaml
environment:
  sdk: ^3.10.4

dependencies:
  flutter: sdk
  cupertino_icons: ^1.0.8      # iOS-style icons
  path_provider: ^2.1.0        # File system access
  
  # Internal packages
  kitako_core: path            # Core types
  kitako_normalizer: path      # Taglish normalizer
  kitako_ffi: path             # Native FFI bindings
  kitako_embedding: path       # TFLite embeddings
  kitako_ann: path             # ANN search

dev_dependencies:
  flutter_test: sdk
  flutter_lints: ^6.0.0        # Lint rules
```

### Core Package (`kitako_core`)

```yaml
environment:
  sdk: ^3.10.4
  flutter: ">=1.17.0"

dependencies:
  flutter: sdk

dev_dependencies:
  flutter_test: sdk
  flutter_lints: ^6.0.0
```

### Normalizer Package (`kitako_normalizer`)

```yaml
environment:
  sdk: ^3.10.4
  flutter: ">=1.17.0"

dependencies:
  flutter: sdk

dev_dependencies:
  flutter_test: sdk
  flutter_lints: ^6.0.0
```

**Description**: Taglish text normalizer for Filipino/Tagalog/English code-switching, abbreviations, and text speak.

### Embedding Package (`kitako_embedding`)

```yaml
environment:
  sdk: ^3.10.4
  flutter: ">=1.17.0"

dependencies:
  flutter: sdk
  tflite_flutter: ^0.11.0      # TensorFlow Lite inference
  image: ^4.3.0                # Image processing

dev_dependencies:
  flutter_test: sdk
  flutter_lints: ^6.0.0
```

### ANN Package (`kitako_ann`)

```yaml
environment:
  sdk: ^3.10.4
  flutter: ">=1.17.0"

dependencies:
  flutter: sdk
  kitako_ffi: path             # Native HNSW bindings
  path_provider: ^2.1.0        # File system access

dev_dependencies:
  flutter_test: sdk
  flutter_lints: ^6.0.0
  test: ^1.26.3                # Unit testing
```

**Description**: HNSW-based Approximate Nearest Neighbor search for multimodal image retrieval.

### FFI Plugin Package (`kitako_ffi`)

```yaml
environment:
  sdk: ^3.10.4
  flutter: ">=3.3.0"

dependencies:
  flutter: sdk
  plugin_platform_interface: ^2.0.2   # Platform plugin interface
  ffi: ^2.1.3                         # Dart FFI support

dev_dependencies:
  ffigen: ^13.0.0              # C header bindings generator
  flutter_test: sdk
  flutter_lints: ^6.0.0
```

---

## Native Dependencies

### HNSW Library (hnswlib)

| Property | Value |
|----------|-------|
| **Library** | hnswlib (Header-only C++ library) |
| **Source** | [nmslib/hnswlib](https://github.com/nmslib/hnswlib) |
| **C++ Standard** | C++14 |
| **Language** | C++ with C API wrapper |

### Native Source Files

```
packages/kitako_ffi/src/
├── CMakeLists.txt       # CMake build configuration
├── kitako_ffi.c         # C FFI exports
├── kitako_ffi.h         # C FFI header
├── kitako_ann.cpp       # HNSW C++ implementation
├── kitako_ann.h         # HNSW C API header
└── hnswlib/             # hnswlib header-only library
```

### C API Functions

```c
// Index management
KitakoAnnHandle kitako_ann_create(int32_t dim, int32_t space_type);
int32_t kitako_ann_load(KitakoAnnHandle handle, const char* index_path);
void kitako_ann_free(KitakoAnnHandle handle);

// Search
int32_t kitako_ann_search(
    KitakoAnnHandle handle,
    const float* query,
    int32_t k,
    int64_t* result_ids,
    float* result_distances
);

// Space types
KITAKO_SPACE_IP = 0     // Inner Product (cosine for normalized vectors)
KITAKO_SPACE_L2 = 1     // Euclidean distance
KITAKO_SPACE_COSINE = 2 // Cosine similarity
```

---

## Machine Learning Models

### Model Specifications

| Model | Format | Dimension | Purpose |
|-------|--------|-----------|---------|
| **Text Encoder** | TFLite | 768 | SigLIP text embeddings |
| **Image Encoder** | TFLite (INT8) | 768 | SigLIP image embeddings |
| **Tokenizer** | JSON/Jinja | - | Text tokenization |

### Model Files Structure

```
assets/models/
├── embeddings/
│   ├── embed_model.json
│   └── embed_model.tflite
├── image_encoder/
│   └── kitako_image_encoder_int8.tflite
├── text_encoder/
│   └── kitako_text_encoder_dynamic.tflite
└── tokenizer/
    ├── chat_template.jinja
    ├── config.json
    ├── merges.txt
    ├── preprocessor_config.json
    ├── special_tokens_map.json
    ├── tokenizer_config.json
    ├── tokenizer.json
    └── vocab.json
```

### Index Files Structure

```
assets/indexes/
└── ann/
    └── ann_index.meta.json
```

---

## Build Tools

### FFI Bindings Generation

```bash
# Generate Dart FFI bindings from C headers
cd packages/kitako_ffi
dart run ffigen --config ffigen.yaml
```

**ffigen Configuration** (`ffigen.yaml`):
```yaml
name: KitakoFfiBindings
output: 'lib/kitako_ffi_bindings_generated.dart'
headers:
  entry-points:
    - 'src/kitako_ffi.h'
```

### CMake Build Configuration

```cmake
cmake_minimum_required(VERSION 3.10)
project(kitako_ffi_library VERSION 0.0.1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization for release builds
if (CMAKE_BUILD_TYPE STREQUAL "Release")
  target_compile_options(kitako_ffi PRIVATE -O3 -ffast-math)  # GCC/Clang
  target_compile_options(kitako_ffi PRIVATE /O2 /fp:fast)     # MSVC
endif()
```

---

## Platform-Specific Requirements

### Android

| Requirement | Specification |
|-------------|---------------|
| **Min SDK** | Defined in app/build.gradle |
| **NDK** | Required for native compilation |
| **Repositories** | google(), mavenCentral() |
| **Page Size** | Supports Android 15 16KB page size |

```gradle
// Native linker flags for Android 15 support
target_link_options(kitako_ffi PRIVATE "-Wl,-z,max-page-size=16384")
```

### iOS / macOS

| Requirement | Specification |
|-------------|---------------|
| **Xcode** | Latest stable version |
| **CocoaPods** | For dependency management |
| **Visibility** | `-fvisibility=default` |

### Windows

| Requirement | Specification |
|-------------|---------------|
| **Visual Studio** | 2019+ with C++ workload |
| **Windows SDK** | 10.0+ |
| **CMake** | Bundled or standalone |

### Linux

| Requirement | Specification |
|-------------|---------------|
| **GCC/Clang** | C++14 capable |
| **CMake** | 3.10+ |
| **GTK** | For Flutter desktop |

---

## Dependency Matrix

### Complete Package Dependencies

| Package | Flutter | tflite_flutter | image | ffi | path_provider | Internal Deps |
|---------|---------|----------------|-------|-----|---------------|---------------|
| kitako_app | ✅ | - | - | - | ✅ | core, normalizer, ffi, embedding, ann |
| kitako_core | ✅ | - | - | - | - | - |
| kitako_normalizer | ✅ | - | - | - | - | - |
| kitako_embedding | ✅ | ✅ | ✅ | - | - | - |
| kitako_ann | ✅ | - | - | - | ✅ | ffi |
| kitako_ffi | ✅ | - | - | ✅ | - | - |

### Version Summary

| Dependency | Version | Usage |
|------------|---------|-------|
| `flutter` | SDK | Core framework |
| `cupertino_icons` | ^1.0.8 | iOS icons |
| `path_provider` | ^2.1.0 | File system paths |
| `tflite_flutter` | ^0.11.0 | TensorFlow Lite |
| `image` | ^4.3.0 | Image processing |
| `ffi` | ^2.1.3 | FFI support |
| `plugin_platform_interface` | ^2.0.2 | Platform plugins |
| `flutter_lints` | ^6.0.0 | Code linting |
| `ffigen` | ^13.0.0 | FFI code generation |
| `test` | ^1.26.3 | Unit testing |

---

## Quick Reference Commands

### Install Dependencies

```bash
# From workspace root
flutter pub get

# For individual packages
cd packages/kitako_normalizer && flutter pub get
cd packages/kitako_embedding && flutter pub get
cd packages/kitako_ann && flutter pub get
cd packages/kitako_ffi && flutter pub get
cd apps/kitako_app && flutter pub get
```

### Run Tests

```bash
# All packages
flutter test

# Specific package
cd packages/kitako_normalizer && flutter test
cd packages/kitako_ann && flutter test
```

### Build Application

```bash
cd apps/kitako_app

# Windows
flutter build windows

# Android
flutter build apk

# iOS
flutter build ios

# Web
flutter build web
```

### Run Application

```bash
cd apps/kitako_app

# Windows desktop
flutter run -d windows

# Chrome
flutter run -d chrome

# Connected device
flutter run
```

---

## License & Attribution

- **hnswlib**: Apache 2.0 License - [nmslib/hnswlib](https://github.com/nmslib/hnswlib)
- **TensorFlow Lite**: Apache 2.0 License
- **SigLIP Model**: Google Research

---

*Document generated for KitaKo System methodology documentation.*
*Last updated: January 2026*
