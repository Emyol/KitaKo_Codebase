# KitaKo App - Screen Flow Diagram

## Visual Flow

```
┌─────────────────────────────────────────┐
│                                         │
│         STARTUP SCREEN                  │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │                                 │   │
│  │      [Animated Logo]            │   │
│  │                                 │   │
│  │      ⚪ Loading...              │   │
│  │                                 │   │
│  └─────────────────────────────────┘   │
│                                         │
│         (Auto 3 seconds)                │
│              ↓                          │
└─────────────────────────────────────────┘


┌─────────────────────────────────────────┐
│  Search                    ⚙️            │
├─────────────────────────────────────────┤
│                                         │
│  ┌───┐ ┌───┐ ┌───┐                     │
│  │ □ │ │ □ │ │ □ │   HOME SCREEN       │
│  └───┘ └───┘ └───┘                     │
│  ┌───┐ ┌───┐ ┌───┐   (Gallery View)    │
│  │ □ │ │ □ │ │ □ │                     │
│  └───┘ └───┘ └───┘                     │
│  ┌───┐ ┌───┐ ┌───┐                     │
│  │ □ │ │ □ │ │ □ │                     │
│  └───┘ └───┘ └───┘                     │
│                                         │
├─────────────────────────────────────────┤
│  🔍 Search...              ⚙️            │
└─────────────────────────────────────────┘
        ↓ tap                  ↓ tap

┌─────────────────────┐   ┌───────────────────────┐
│  ← Search      ⚙️    │   │  ← Settings           │
├─────────────────────┤   ├───────────────────────┤
│                     │   │                       │
│   [Logo/Results]    │   │  Personalization      │
│                     │   │  ├ Title colour    ⭘  │
│   OR                │   │  └ Highlight      ⭘  │
│                     │   │                       │
│   ╔═══════════╗     │   │  System               │
│   ║ No result ║     │   │  ├ Setting 1      ⭘  │
│   ║ has been  ║     │   │  ├ Setting 2      ⭘  │
│   ║ found     ║     │   │  └ Setting 3      ⭘  │
│   ╚═══════════╝     │   │                       │
│                     │   │                       │
├─────────────────────┤   └───────────────────────┘
│ 🔍 [Query]  ×  ➤   │     SETTINGS SCREEN
└─────────────────────┘
   SEARCH SCREEN
```

## Screen Details

### 1️⃣ Startup Screen

**Duration**: 3 seconds

- Animated logo (fade + scale)
- Loading indicator
- Gradient background
- **Auto navigates** to Home Screen

---

### 2️⃣ Home Screen (Main)

**Components**:

- **App Bar**: "Search" title + Settings icon (⚙️)
- **Gallery Grid**: 3×3 placeholder images
- **Search Bar**: Fixed at bottom

**Actions**:

- Tap Search Bar → Opens Search Screen (slide up)
- Tap Settings Icon → Opens Settings Screen

---

### 3️⃣ Search Screen

**States**:

#### A) Default (before search)

```
┌─────────────────┐
│                 │
│   [KitaKo Logo] │
│                 │
└─────────────────┘
```

#### B) Searching

```
┌─────────────────┐
│   ⏳ Loading    │
│ Searching for   │
│   "query"...    │
└─────────────────┘
```

#### C) Results Found

```
┌─────────────────┐
│ Query Text  ⚙️   │
│ ┌─┐ ┌─┐ ┌─┐    │
│ │□│ │□│ │□│    │
│ └─┘ └─┘ └─┘    │
│ ┌─┐ ┌─┐ ┌─┐    │
│ │□│ │□│ │□│    │
│ └─┘ └─┘ └─┘    │
└─────────────────┘
```

#### D) No Results

```
┌─────────────────┐
│   ╔═══════╗     │
│   ║  🔍❌  ║     │
│   ║No result    │
│   ║has been     │
│   ║found        │
│   ╚═══════╝     │
└─────────────────┘
```

**Components**:

- Active search input
- Clear button (×)
- Send button (➤)
- Auto-focus keyboard

---

### 4️⃣ Settings Screen

**Sections**:

```
Personalization
├─ Title colour         [Toggle]
└─ Highlight colour     [Toggle]

System
├─ System setting 1     [Toggle]
├─ System setting 2     [Toggle]
└─ System setting 3     [Toggle]
```

---

## Color Reference

```
Background:   ▓▓▓ #1A1A1A (Dark Gray)
Surface:      ▓▓▓ #2A2A2A (Card Gray)
Primary:      🔵 #4A90E2 (Blue)
Secondary:    🔵 #5BA3F5 (Light Blue)
Accent:       🔵 #1E3A5F (Dark Blue)
Text:         ⚪ #FFFFFF (White)
Hint:         ▒▒▒ #666666 (Gray)
```

---

## File Structure

```
lib/
├── main.dart                         # Entry point + Theme
└── src/
    └── ui/
        ├── screens/
        │   ├── startup_screen.dart   # Screen 1
        │   ├── home_screen.dart      # Screen 2
        │   ├── search_screen.dart    # Screen 3
        │   └── settings_screen.dart  # Screen 4
        └── theme/
            └── app_theme.dart        # Colors, Styles, Dimensions
```

---

## Testing Guide

### Test Navigation:

1. ✅ App starts → Startup screen (3s) → Home screen
2. ✅ Home → Tap search bar → Search screen (slide up)
3. ✅ Home → Tap settings icon → Settings screen
4. ✅ Search/Settings → Tap back → Returns to Home

### Test Search:

1. ✅ Type "dog" → See results grid
2. ✅ Type "cat" → See results grid
3. ✅ Type "food" → See results grid
4. ✅ Type "pizza" → See "No results" message
5. ✅ Clear text → See logo again

### Test Settings:

1. ✅ Toggle switches work
2. ✅ All 5 settings are toggleable
3. ✅ UI updates immediately

---

## Status: ✅ Complete

All screens implemented and tested!
Ready for backend integration.

**Last Updated**: January 25, 2026
