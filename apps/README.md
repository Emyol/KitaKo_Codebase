# 📱 KitaKo - Mobile Image Retrieval App

A Flutter-based mobile application for intelligent image search and retrieval.

## Platform

**Mobile Application** for:

- 📱 **Android** - Smartphones and tablets (API 21+)
- 🍎 **iOS** - iPhone and iPad (iOS 12.0+)

**Orientation**: Portrait mode only

---

## Quick Start

```bash
# Navigate to app
cd apps/kitako_app

# Install dependencies
flutter pub get

# Run on mobile device/emulator
flutter run
```

---

## Features

✅ **Startup Screen** - Animated loading with logo  
✅ **Gallery View** - Grid display of images (3 columns)  
✅ **Smart Search** - Text-based image retrieval  
✅ **Search Results** - Visual feedback for found/not found  
✅ **Settings** - User customization options  
✅ **Portrait Lock** - Optimized for vertical mobile use  
✅ **Dark Theme** - Modern UI with blue accents  
✅ **Smooth Animations** - Polished transitions

---

## Mobile Setup

### For Android

1. Install Android Studio with SDK
2. Create/start an Android Virtual Device (AVD)
3. Run: `flutter run`

### For iOS (macOS only)

1. Install Xcode from App Store
2. Open iOS Simulator
3. Run: `flutter run -d ios`

**Detailed setup**: See [MOBILE_SETUP.md](MOBILE_SETUP.md)

---

## Documentation

- 📱 [MOBILE_SETUP.md](MOBILE_SETUP.md) - Mobile-specific setup guide
- 🚀 [QUICK_START.md](QUICK_START.md) - Get started quickly
- 📋 [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - What's implemented
- 📖 [UI_README.md](UI_README.md) - Technical UI documentation
- 🗺️ [SCREEN_FLOW.md](SCREEN_FLOW.md) - Screen navigation flow

---

## Current Status

✅ **Frontend Complete** - All screens implemented  
✅ **Backend Integrated** - Services wired to real packages  
✅ **Mobile Optimized** - Touch-friendly interface  
✅ **Desktop Support** - Windows, macOS, Linux  
✅ **Portrait Only** - Locked orientation

### Service Status

| Service | Real | Fallback | Notes |
|---------|------|----------|-------|
| **TaglishNormalizer** | ✅ | - | Fully implemented |
| **EmbeddingService** | ⏳ | ✅ Mock | Needs TFLite DLL |
| **ANNSearchService** | ⏳ | ✅ Brute-force | Needs index file |

### Enable Real Services

**For TFLite Embeddings (Windows):**
1. Download from [tflite-flutter-prebuilt](https://github.com/peterfritz/tflite-flutter-plugin-prebuilt/releases)
2. Place `libtensorflowlite_c-win.dll` in `blobs/` folder
3. Run `flutter clean && flutter run`

**For HNSW Index:**
1. Build index with `tools/build_index.dart`
2. Copy output to `assets/index/`

---

## Testing

### Test Search:

- Type **"dog"**, **"cat"**, or **"food"** → See results  
- Type Taglish queries → See normalized query display
- Type anything else → See "No results" message

### Test Taglish Normalization:

- Type **"nagshopping aq"** → Normalizes to "nag shopping ako"
- Type **"gutom n aq kc d p kumain"** → Normalizes to "gutom na ako kasi di pa kumain"

### Test Navigation:

- Home → Tap search → Search screen opens
- Home → Tap settings → Settings screen opens
- Use back button to navigate

### Test on Desktop:

```bash
# Windows
flutter run -d windows

# macOS  
flutter run -d macos

# Linux
flutter run -d linux
```

### Test on Mobile:

```bash
# Check connected devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Run in release mode (better performance)
flutter run --release
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter UI                               │
│                    (SearchScreen, Results)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ImageSearchService                            │
│              (Orchestrates the search flow)                      │
└─────────────────────────────────────────────────────────────────┘
        │                     │                      │
        ▼                     ▼                      ▼
┌───────────────┐   ┌─────────────────┐   ┌─────────────────────┐
│ TaglishNorm   │   │ EmbeddingService│   │   ANNSearchService  │
│ (Normalizer)  │   │ (kitako_embed)  │   │   (kitako_ann)      │
└───────────────┘   └─────────────────┘   └─────────────────────┘
                            │                        │
                            ▼                        ▼
                    ┌───────────────┐        ┌─────────────┐
                    │  TFLite Model │        │ Native HNSW │
                    │   (SigLIP)    │        │    (FFI)    │
                    └───────────────┘        └─────────────┘
```

---

## Project Structure

```
apps/kitako_app/
├── android/              # Android native files
├── ios/                  # iOS native files
├── blobs/                # Native DLLs (TFLite)
├── lib/
│   ├── main.dart         # App entry point
│   └── src/
│       ├── models/       # Data models
│       ├── services/     # Business logic
│       │   ├── embedding_service.dart
│       │   ├── ann_search_service.dart
│       │   └── image_search_service.dart
│       └── ui/
│           ├── screens/  # All app screens
│           └── theme/    # Theming
├── assets/
│   ├── model/            # TFLite models
│   ├── tokenizer/        # SigLIP tokenizer
│   └── index/            # HNSW index
├── setup_tflite.ps1      # TFLite setup script
└── README.md             # This file
```

---

## Tech Stack

- **Framework**: Flutter 3.x
- **Language**: Dart
- **ML Runtime**: TensorFlow Lite
- **ANN Search**: HNSW (hnswlib via FFI)
- **UI**: Material Design 3
- **Platforms**: Android, iOS, Windows, macOS, Linux

---

## Requirements

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio (for Android)
- Xcode (for iOS, macOS only)
- Visual Studio (for Windows)
- CMake 3.10+ (for native builds)

---

**Platform**: 📱 Mobile + 🖥️ Desktop  
**Status**: ✅ End-to-End Wired (with fallbacks)  
**Last Updated**: January 27, 2026
