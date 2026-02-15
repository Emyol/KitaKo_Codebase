# 📱 Mobile Development Tips for KitaKo

## Running on Mobile Devices

### Android

#### Physical Device

1. Enable Developer Options on your phone:
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times
2. Enable USB Debugging:
   - Settings → Developer Options → USB Debugging

3. Connect phone via USB

4. Run:
   ```bash
   flutter devices  # Verify device is detected
   flutter run      # Install and run app
   ```

#### Android Emulator

1. Open Android Studio → AVD Manager
2. Create a device (recommended: Pixel 7, API 33+)
3. Start emulator
4. Run: `flutter run`

**Tip**: Use hardware acceleration for better emulator performance!

---

### iOS

#### iOS Simulator (macOS only)

1. Open Xcode
2. Xcode → Open Developer Tool → Simulator
3. Choose device (iPhone 14, etc.)
4. Run: `flutter run -d ios`

**Keyboard shortcut in simulator**: Cmd+K

#### Physical iPhone/iPad

1. Connect device via cable
2. Trust computer on device
3. In Xcode, add your Apple ID
4. Run: `flutter run`

**Note**: May need Apple Developer account for physical device testing

---

## Mobile-Specific Features in KitaKo

### Portrait Orientation Lock ✅

```dart
// Already implemented in main.dart
SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
]);
```

The app **won't rotate** to landscape - optimal for image browsing!

### Touch-Optimized UI ✅

- Large tap targets (48x48 minimum)
- Bottom search bar (easy thumb reach)
- Swipe gestures for navigation
- Native keyboard integration

### SafeArea Handling ✅

```dart
// Already wrapped in SafeArea widgets
SafeArea(
  child: // Bottom search bar
)
```

Works with:

- iPhone notches
- Android punch-holes
- Navigation bars
- Status bars

---

## Mobile Testing Checklist

### Different Screen Sizes

Test on various devices:

**Small (5" - 5.5")**

- [x] iPhone SE (2022)
- [x] Small Android phones
- [x] Check grid spacing

**Medium (6" - 6.7")**

- [x] iPhone 14/15
- [x] Most Android phones
- [x] Primary target

**Large (7"+)**

- [x] iPad
- [x] Android tablets
- [x] Verify grid adapts

### Interaction Testing

- [x] Tap search bar → Smooth slide up
- [x] Keyboard appears automatically
- [x] Type and search works
- [x] Back button navigates correctly
- [x] Settings toggles respond
- [x] Grid scrolls smoothly

### Performance Testing

```bash
# Test in release mode
flutter run --release

# Profile performance
flutter run --profile

# Check app size
flutter build apk --analyze-size
```

---

## Common Mobile Scenarios

### 1. App Backgrounding

**Expected behavior**:

- App state preserved
- Returns to same screen
- Search text maintained

**Test**: Press home button, reopen app

### 2. Keyboard Handling

**Expected behavior**:

- Auto-focus in search screen
- Shows soft keyboard
- Send button works
- Clear button visible when typing

**Test**: Open search, type text, submit

### 3. Memory Management

**Current**: Placeholder images (low memory)
**Future**: Real images (implement caching)

---

## Mobile Performance Optimization

### Already Implemented ✅

- Efficient grid layout
- Minimal rebuilds
- Proper widget disposal
- Optimized animations

### When Adding Backend

1. **Image Caching**

   ```dart
   // Use cached_network_image package
   CachedNetworkImage(
     imageUrl: imageUrl,
     placeholder: (context, url) => CircularProgressIndicator(),
     errorWidget: (context, url, error) => Icon(Icons.error),
   )
   ```

2. **Lazy Loading**
   - Load images on demand
   - Implement pagination
   - Clear cache when memory low

3. **Background Processing**
   - Use Isolates for heavy computations
   - Keep UI thread responsive

---

## Mobile Debugging

### Debug Console

```bash
# Verbose logging
flutter run -v

# Clear logs
Ctrl+L (in terminal)

# Filter logs
flutter logs | grep "MyTag"
```

### Hot Reload on Mobile

1. Save file in editor
2. Watch device update instantly
3. Or press `r` in terminal

**Hot Restart**: Press `R` for full restart

### Common Issues

**Issue**: App crashes on startup

```bash
# Solution
flutter clean
flutter pub get
flutter run
```

**Issue**: Slow on emulator

```bash
# Solution
flutter run --release  # Much faster
```

**Issue**: Keyboard not showing

```bash
# Android: Enable soft input in emulator settings
# iOS: Press Cmd+K in simulator
```

---

## Mobile Build Sizes

Current size (release):

- Android APK: ~20-25 MB
- iOS IPA: ~25-30 MB

With images (future):

- Will increase based on cached images
- Implement cleanup strategies

---

## Mobile Gestures (Future Enhancements)

### Potential Additions:

- **Swipe to delete** (search history)
- **Pinch to zoom** (image preview)
- **Pull to refresh** (gallery)
- **Long press** (image options)
- **Double tap** (quick actions)

All ready to implement when backend is integrated!

---

## Platform-Specific Code

### Android Permissions (When needed)

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

### iOS Permissions (When needed)

```xml
<!-- ios/Runner/Info.plist -->
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photos for image search</string>
```

---

## Testing on Real Devices

### Why Test on Real Devices?

- Accurate performance
- Real touch interactions
- Actual battery usage
- True network conditions
- Real camera/sensors

### Recommended Test Devices

1. Mid-range Android phone (most users)
2. iPhone (latest or previous gen)
3. Low-end device (performance check)
4. Tablet (large screen check)

---

## Mobile Deployment Checklist

Before submitting to stores:

### Android (Google Play)

- [x] Update version in pubspec.yaml
- [x] Create app icons (all sizes)
- [x] Generate signing key
- [x] Build release: `flutter build appbundle`
- [x] Test on multiple devices
- [x] Prepare store listing
- [x] Add screenshots
- [x] Write description

### iOS (App Store)

- [x] Update version in pubspec.yaml
- [x] Create app icons (all sizes)
- [x] Configure signing in Xcode
- [x] Build release: `flutter build ipa`
- [x] Test on devices
- [x] Prepare App Store Connect
- [x] Add screenshots
- [x] Submit for review

---

## Mobile-First Design Principles (Already Applied)

✅ **Touch-friendly** - Buttons 48x48 or larger  
✅ **Thumb-reach** - Important actions at bottom  
✅ **Portrait-optimized** - Locked orientation  
✅ **Clear hierarchy** - Easy to scan  
✅ **Responsive** - Works on all sizes  
✅ **Native feel** - Material Design 3  
✅ **Fast feedback** - Immediate visual response

---

## Quick Mobile Commands Reference

```bash
# Check Flutter setup for mobile
flutter doctor

# List connected devices
flutter devices

# Run on Android
flutter run

# Run on iOS
flutter run -d ios

# Build Android APK
flutter build apk

# Build iOS (macOS only)
flutter build ios

# Check app size
flutter build apk --analyze-size

# Release mode (fast)
flutter run --release

# Clean project
flutter clean
```

---

**Platform**: 📱 Android & iOS Mobile  
**Orientation**: Portrait Only  
**Status**: ✅ Mobile-Optimized

**Last Updated**: January 25, 2026
