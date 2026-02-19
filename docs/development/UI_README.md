# KitaKo Flutter Mobile UI Documentation

This document describes the frontend implementation of the KitaKo Image Retrieval System mobile application based on the Figma design.

## Platform

**Mobile Application** - Built with Flutter for:

- Android (smartphones and tablets)
- iOS (iPhone and iPad)

**Orientation**: Portrait mode only (locked via SystemChrome)

---

## Project Structure

```
lib/
├── main.dart                          # App entry point with theme configuration
└── src/
    └── ui/
        └── screens/
            ├── startup_screen.dart     # Initial loading screen
            ├── home_screen.dart        # Gallery view with search bar
            ├── search_screen.dart      # Search interface with results
            └── settings_screen.dart    # Settings page
```

## Screens Overview

### 1. Startup Screen (`startup_screen.dart`)

- **Purpose**: Initial loading screen shown when app launches
- **Features**:
  - Animated logo with fade and scale effects
  - Loading indicator
  - Auto-navigates to home screen after 3 seconds
  - Gradient background
- **Note**: Logo uses placeholder design - replace with actual assets when available

### 2. Home Screen (`home_screen.dart`)

- **Purpose**: Main gallery view displaying user's images
- **Features**:
  - AppBar with title "Search" and settings icon
  - 3-column grid layout for image gallery
  - Bottom search bar with slide-up animation
  - Placeholder images (gray boxes with image icons)
- **Interactions**:
  - Tap search bar → Opens search screen with slide-up transition
  - Tap settings icon → Opens settings screen
- **Note**: Gallery currently shows placeholder boxes - will display actual images from backend

### 3. Search Screen (`search_screen.dart`)

- **Purpose**: Interactive search interface with keyboard and results
- **Features**:
  - Auto-focuses search input on open
  - Active search bar with clear and send buttons
  - Three states:
    1. **Default**: Shows logo (before search)
    2. **Searching**: Shows loading indicator with search query
    3. **Results**: Shows grid of matching images
    4. **No Results**: Shows "No result has been found" message with icon
- **Mock Search Logic**:
  - Returns results for queries containing: "dog", "cat", "food"
  - Shows no results for other queries
  - 2-second simulated search delay
- **Note**: Replace mock logic with actual backend integration

### 4. Settings Screen (`settings_screen.dart`)

- **Purpose**: User customization and system settings
- **Features**:
  - Two sections: Personalization and System
  - Toggle switches for:
    - Personalization:
      - Title colour
      - Highlight colour
    - System:
      - System setting 1
      - System setting 2
      - System setting 3
- **Note**: Settings currently have no effect - implement functionality based on requirements

## Theme Configuration

The app uses a dark theme with blue accents matching the Figma design:

### Colors

- **Background**: `#1A1A1A` (dark gray)
- **Surface**: `#2A2A2A` (lighter gray)
- **Primary**: `#4A90E2` (blue)
- **Secondary**: `#5BA3F5` (lighter blue)
- **Accent**: `#1E3A5F` (dark blue - used for titles and icons)

### Typography

- **App Bar Title**: 24px, Bold, Dark Blue
- **Body Text**: 16px, White
- **Section Headers**: 20px, Bold, White
- **Hints**: 16px, Gray (#666666)

## Navigation Flow

```
StartupScreen (3s auto-transition)
    ↓
HomeScreen
    ├→ SearchScreen (slide up transition)
    └→ SettingsScreen
```

## Backend Integration Points

When implementing the backend, update these areas:

### 1. Home Screen Gallery

- Replace `_placeholderColors` list with actual image data
- Load images from device storage or backend
- Update `GridView.builder` to display real images

### 2. Search Functionality

- Replace mock search logic in `_performSearch()` method
- Integrate with embedding and ANN search services
- Handle real-time results and updates

### 3. Settings Persistence

- Save settings to local storage or user preferences
- Apply theme changes based on personalization settings
- Implement system settings functionality

## Mock Data Notes

### Current Placeholders:

1. **Images**: Gray boxes with image icon placeholders
2. **Search Results**: Hardcoded color list for demonstration
3. **Search Logic**: Simple string matching for demo purposes

### To Replace:

- Use actual image assets from user's gallery
- Implement real search with kitako_embedding and kitako_ann packages
- Load real user preferences for settings

## Running the App

```bash
# Navigate to app directory
cd apps/kitako_app

# Get dependencies
flutter pub get

# Run on Android device/emulator
flutter run

# Run on iOS device/simulator (macOS only)
flutter run -d ios

# Check available devices
flutter devices
```

## Testing Search Results

To see different states:

- Search for "dog", "cat", or "food" → See results grid
- Search for anything else → See "No results" state
- Leave search empty → See default logo state

## Future Enhancements

1. **Image Loading**: Add actual image loading from device storage
2. **Search History**: Store and display recent searches
3. **Filters**: Implement the filter icon functionality
4. **Image Preview**: Add full-screen image preview on tap
5. **Pull to Refresh**: Refresh gallery images
6. **Animations**: Add more transitions and micro-interactions
7. **Error Handling**: Better error states and messages
8. **Loading States**: Skeleton loaders for image grids

## Dependencies

Current dependencies used:

- `flutter/material.dart` - Material Design widgets
- `flutter/services.dart` - System services (orientation lock)

No additional packages required for frontend functionality.

## Notes for Backend Integration

The UI is ready for backend integration. Key integration points:

1. **Image Retrieval Service**: Connect to local image storage or backend API
2. **Embedding Service**: Use `kitako_embedding` for query processing
3. **ANN Search**: Use `kitako_ann` for similarity search
4. **State Management**: Consider adding Provider/Riverpod for complex state
5. **Caching**: Implement image caching for better performance

---

**Created**: January 25, 2026
**Status**: Frontend Complete - Ready for Backend Integration
