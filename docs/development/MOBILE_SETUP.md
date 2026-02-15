# 📱 Mobile Setup Guide - KitaKo App

## Platform Overview

KitaKo is a **mobile-first image retrieval application** designed for:

- 📱 Android smartphones and tablets
- 🍎 iOS iPhones and iPads

**Screen Orientation**: Portrait only (vertical)

---

## Quick Start for Mobile

### Android Setup

#### 1. Install Android Studio

- Download from https://developer.android.com/studio
- Install Android SDK and platform tools
- Set up at least one Android Virtual Device (AVD)

#### 2. Run on Android

```bash
# Check devices
flutter devices

# Run on connected device or emulator
flutter run

# Or specify device
flutter run -d <device-id>
```

#### 3. Android Emulator Quick Start

- Open Android Studio → AVD Manager
- Create/Start an emulator (recommended: Pixel 7, API 33+)
- In terminal: `flutter run`

---

### iOS Setup (macOS Only)

#### 1. Install Xcode

- Download from Mac App Store
- Open Xcode and install additional components
- Accept license: `sudo xcodlicense --agree`

#### 2. iOS Simulator

```bash
# List simulators
xcrun simctl list devices

# Open simulator
open -a Simulator

# Run app
flutter run -d ios
```

#### 3. Physical iOS Device

- Connect iPhone/iPad via USB
- Trust computer on device
- Run: `flutter run`

---

## Mobile-Specific Features

### Portrait Lock

The app is locked to portrait orientation for optimal mobile experience:

```dart
SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
]);
```

### Touch Interactions

- **Tap** search bar → Opens search screen
- **Swipe down** → Keyboard appears (auto-focus)
- **Tap** settings icon → Opens settings
- **Tap** back button → Returns to previous screen
- **Tap** send button → Executes search

### Mobile Keyboard

- Auto-focuses in search screen
- Show/hide automatically
- Send button on keyboard works for search

---

## Testing on Different Devices

### Android Devices

```bash
# Pixel phones (small)
flutter run -d <pixel-device>

# Tablets (large)
flutter run -d <tablet-device>
```

### iOS Devices

```bash
# iPhone (small/medium)
flutter run -d iPhone

# iPad (large)
flutter run -d iPad
```

---

## Screen Sizes Supported

The app is designed to work on various mobile screen sizes:

### Small (4.7" - 5.5")

- iPhone SE, iPhone 8
- Small Android phones
- ✅ Optimized layout

### Medium (5.8" - 6.7")

- iPhone 12/13/14/15
- Most modern Android phones
- ✅ Primary target size

### Large (7" - 12.9")

- iPads
- Android tablets
- ✅ Adaptive grid layout

---

## Mobile Build Commands

### Development Build

```bash
# Android APK
flutter build apk

# iOS (macOS only)
flutter build ios
```

### Release Build

```bash
# Android App Bundle (for Play Store)
flutter build appbundle

# iOS (for App Store - macOS only)
flutter build ipa
```

---

## Mobile Debugging

### Hot Reload (Mobile)

1. Make code changes
2. Save file
3. Changes appear instantly on device
4. Or press `r` in terminal

### Debugging on Real Device

#### Android

```bash
# Enable USB debugging on device
# Settings → Developer Options → USB Debugging

# Connect via USB
adb devices

# Run app
flutter run
```

#### iOS

```bash
# Connect iPhone/iPad via cable
# Trust computer on device

# Run app
flutter run
```

### Wireless Debugging (Android 11+)

```bash
# Enable wireless debugging on device
# Settings → Developer Options → Wireless Debugging

# Get device IP
adb pair <ip>:<port>

# Run wirelessly
flutter run
```

---

## Mobile Performance Tips

### Image Loading (When Backend Ready)

- Use `cached_network_image` for caching
- Implement lazy loading in grid
- Optimize image sizes for mobile screens

### Memory Management

- Dispose controllers properly
- Clear image cache when needed
- Monitor memory usage

### Battery Optimization

- Minimize background processes
- Reduce animation overhead
- Efficient network calls

---

## Common Mobile Issues

### Issue: Keyboard Not Showing

**Solution**:

- Android: Enable soft keyboard in emulator settings
- iOS: Press Cmd+K in simulator
- Physical device: Should work automatically

### Issue: App Not Installing

**Solution**:

```bash
# Clear build cache
flutter clean
flutter pub get

# Rebuild
flutter run
```

### Issue: Slow Performance

**Solution**:

- Use release mode: `flutter run --release`
- Enable hardware acceleration in emulator
- Test on physical device for accurate performance

### Issue: SafeArea Not Working

**Solution**:

- Already implemented in search bar
- Check device notch/cutout settings
- Test on devices with different notches

---

## Mobile Testing Checklist

Test on different devices:

- [x] Small phone (5")
- [x] Medium phone (6.5")
- [x] Large phone (6.7"+)
- [x] Tablet (10"+)

Test orientations:

- [x] Portrait (locked)
- [x] Landscape (should not rotate)

Test interactions:

- [x] Touch/tap gestures
- [x] Keyboard input
- [x] Scroll in grid
- [x] Navigation transitions
- [x] Back button

Test states:

- [x] Fresh install
- [x] App backgrounded
- [x] App restored
- [x] Low memory
- [x] No network (when backend added)

---

## Deployment (When Ready)

### Android (Google Play)

1. Build release: `flutter build appbundle`
2. Sign with keystore
3. Upload to Play Console
4. Submit for review

### iOS (App Store)

1. Build release: `flutter build ipa`
2. Sign with certificates
3. Upload via Xcode or Transporter
4. Submit to App Store Connect

---

## Mobile Development Tools

### Recommended VSCode Extensions

- Flutter
- Dart
- Android iOS Emulator
- Flutter Widget Snippets

### Useful Commands

```bash
# Check Flutter setup
flutter doctor

# List devices
flutter devices

# Check app size
flutter build apk --analyze-size

# Run with profiling
flutter run --profile
```

---

## Platform-Specific Notes

### Android

- Minimum SDK: API 21 (Android 5.0)
- Target SDK: Latest stable
- Permissions: Will need storage access for images

### iOS

- Minimum: iOS 12.0
- Target: Latest iOS version
- Permissions: Photo library access required

---

## Next Steps for Mobile

1. **Test on real devices** - More accurate than emulators
2. **Optimize for different screen sizes** - Already responsive
3. **Add haptic feedback** - For better mobile UX
4. **Implement gestures** - Swipe, pinch to zoom, etc.
5. **Add splash screen** - Native splash for each platform
6. **Configure app icons** - Platform-specific icons
7. **Set up deep linking** - For sharing images

---

**Platform**: 📱 Mobile (Android & iOS)
**Orientation**: Portrait Only
**Status**: ✅ Ready for Mobile Testing

**Last Updated**: January 25, 2026
