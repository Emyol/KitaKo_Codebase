# 🚀 Quick Start Guide - KitaKo Image Retrieval Mobile App

## Prerequisites

- Flutter SDK installed
- Mobile device/emulator ready (Android or iOS)
- For Android: Android Studio with AVD or physical device
- For iOS: Xcode with iOS Simulator or physical device (macOS only)

## Installation & Running

### 1. Navigate to App Directory

```bash
cd apps/kitako_app
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Check Available Devices

```bash
flutter devices
```

### 4. Run the App

```bash
# For Android Emulator/Device
flutter run

# For iOS Simulator/Device (macOS only)
flutter run -d ios

# For specific device
flutter run -d <device-id>
```

## 🧪 Testing the App

### Navigation Test

1. **Launch** → See startup screen with animated logo (3 seconds)
2. **Auto Navigate** → Home screen appears with gallery grid
3. **Tap Search Bar** → Search screen slides up with keyboard
4. **Tap Back** → Returns to home screen
5. **Tap Settings Icon** → Settings screen opens

### Search Functionality Test

#### Test Queries with Results:

- Type: `dog` → Press send → See results grid
- Type: `cat` → Press send → See results grid
- Type: `food` → Press send → See results grid

#### Test Queries without Results:

- Type: `pizza` → Press send → See "No result has been found"
- Type: `car` → Press send → See "No result has been found"

#### Test Clear Function:

- Type any text → Tap **×** button → Text clears

### Settings Test

- Toggle **Title colour** → Switch animates
- Toggle **Highlight colour** → Switch animates
- Toggle **System settings** → All work independently

## 📱 Mobile Platforms

This is a **mobile application** designed for:

- **Android** - Smartphones and tablets
- **iOS** - iPhone and iPad (requires macOS for development)

**Portrait Mode Only** - The app is locked to portrait orientation for the best user experience.

Run `flutter devices` to see available mobile devices/emulators.

## 🎨 What You'll See

### Startup Screen

- Dark background with gradient
- Animated KitaKo logo
- Loading spinner
- → Auto transitions after 3 seconds

### Home Screen

- "Search" title in top left
- Settings icon (⚙️) in top right
- 3×3 grid of placeholder images (gray boxes)
- Search bar at bottom with filter icon

### Search Screen (4 states)

1. **Default**: Logo displayed, search bar ready
2. **Searching**: Loading spinner with "Searching..." message
3. **Results**: Grid of images matching query
4. **No Results**: Icon with "No result has been found" message

### Settings Screen

- Personalization section (2 toggles)
- System section (3 toggles)
- All toggles functional

## 🎯 Expected Behavior

### ✅ Working Features

- Smooth screen transitions
- Keyboard auto-focus in search
- Loading states and animations
- Toggle switches in settings
- Back navigation
- Mock search results

### ⏳ Not Yet Implemented (Frontend Only)

- Real image loading (placeholders shown)
- Actual search with embeddings/ANN
- Settings persistence
- Theme changes from settings
- Filter functionality

## 📸 Screenshots Reference

Based on Figma:

1. ✅ Startup → Logo animation
2. ✅ Home → Gallery grid + search bar
3. ✅ Search → Keyboard visible + logo
4. ✅ No Results → Error state with icon
5. ✅ Settings → Toggle switches

## 🐛 Troubleshooting

### App Won't Run

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

##On Android emulator: Ensure "Show soft input" is enabled

- On iOS simulator: Press Cmd+K to toggle keyboard
- The search screen auto-focuses the input field
- Wait ~300ms for keyboard to appear
- Works best on mobile/tablet simulators

### Images Not Showing

- This is expected! Currently using placeholder boxes
- Backend integration will load real images

## 🔧 Development Tips

### Hot Reload

- Save files to see changes instantly
- Press `r` in terminal for manual reload
- Press `R` for full restart

### Checking Logs

- Terminal shows all debug output
- Look for navigation events
- Search state changes logged

### Modifying Mock Data

To change search behavior, edit `search_screen.dart`:

```dart
// Line ~55-58
final hasResults = _searchController.text.toLowerCase().contains('dog') ||
    _searchController.text.toLowerCase().contains('cat') ||
    _searchController.text.toLowerCase().contains('food');
```

Add more keywords for testing!

## 📂 Project Structure

```
apps/kitako_app/
├── lib/
│   ├── main.dart                    ← App entry
│   └── src/ui/
│       ├── screens/                 ← All 4 screens
│       │   ├── startup_screen.dart
│       │   ├── home_screen.dart
│       │   ├── search_screen.dart
│       │   └── settings_screen.dart
│       └── theme/
│           └── app_theme.dart       ← Colors & styles
├── IMPLEMENTATION_SUMMARY.md        ← Overview
├── UI_README.md                     ← Detailed docs
├── SCREEN_FLOW.md                   ← Visual guide
└── QUICK_START.md                   ← This file
```

## 📖 Documentation

- **QUICK_START.md** (this file) → How to run
- **IMPLEMENTATION_SUMMARY.md** → What was built
- **UI_README.md** → Technical details
- **SCREEN_FLOW.md** → Visual flow diagrams

## 🎉 Success Checklist

After running the app, verify:

- [x] Startup screen appears with logo
- [x] Auto navigates to home after 3s
- [x] Gallery grid displays 9 placeholder boxes
- [x] Search bar is at bottom
- [x] Tapping search opens search screen
- [x] Keyboard appears automatically
- [x] Searching "dog"/"cat"/"food" shows results
- [x] Searching other terms shows no results
- [x] Settings screen has 5 toggles
- [x] Back button returns to previous screen

## ✨ Next Steps

Once backend is ready:

1. Replace placeholder colors with real images
2. Integrate `kitako_embedding` for query processing
3. Integrate `kitako_ann` for similarity search
4. Add image caching
5. Implement settings persistence
6. Add pull-to-refresh on gallery

## 📞 Need Help?

Check:

1. Flutter installation: `flutter doctor`
2. Devices available: `flutter devices`
3. Dependencies installed: `flutter pub get`

---

**Status**: ✅ Ready to Run!
**Last Updated**: January 25, 2026

Happy Testing! 🎨📱
