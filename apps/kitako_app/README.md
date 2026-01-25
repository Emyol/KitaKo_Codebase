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
⏳ **Backend Pending** - Model integration upcoming  
✅ **Mobile Optimized** - Touch-friendly interface  
✅ **Portrait Only** - Locked orientation

### Mock Features (Frontend Only)

- Placeholder images (gray boxes)
- Mock search (responds to "dog", "cat", "food")
- Non-persistent settings

### Ready for Integration

- Image loading from device storage
- Embedding service (`kitako_embedding`)
- ANN search service (`kitako_ann`)
- Settings persistence

---

## Testing

### Test Search:

- Type **"dog"**, **"cat"**, or **"food"** → See results
- Type anything else → See "No results" message

### Test Navigation:

- Home → Tap search → Search screen opens
- Home → Tap settings → Settings screen opens
- Use back button to navigate

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

## Project Structure

```
apps/kitako_app/
├── android/              # Android native files
├── ios/                  # iOS native files
├── lib/
│   ├── main.dart         # App entry point
│   └── src/ui/
│       ├── screens/      # All app screens
│       │   ├── startup_screen.dart
│       │   ├── home_screen.dart
│       │   ├── search_screen.dart
│       │   └── settings_screen.dart
│       └── theme/
│           └── app_theme.dart
├── MOBILE_SETUP.md       # Mobile setup guide
├── QUICK_START.md        # Quick start guide
└── README.md             # This file
```

---

## Tech Stack

- **Framework**: Flutter 3.x
- **Language**: Dart
- **UI**: Material Design 3
- **Platforms**: Android, iOS
- **Orientation**: Portrait only

---

## Requirements

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio (for Android)
- Xcode (for iOS, macOS only)
- Mobile device or emulator

---

**Platform**: 📱 Mobile Only (Android & iOS)  
**Status**: ✅ Frontend Complete  
**Last Updated**: January 25, 2026
