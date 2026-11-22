---
name: KitaKo
description: Taglish-aware photo search that runs entirely on your phone.
colors:
  # Light mode (default theme)
  cobalt: "#2563EB"            # accent / primary action
  cobalt-deep: "#1D4ED8"       # chip text, pressed accent, percentage text
  cobalt-mist: "#DBEAFE"       # accent-soft fills, chip background
  harbor-navy: "#0B2545"       # app-bar titles, headings
  paper-sky: "#F4F7FB"         # page background
  paper-sky-deep: "#E8EEF6"
  surface-white: "#FFFFFF"     # cards, search pill, sheets
  tile-mist: "#E2EAF4"         # photo-tile placeholder, surface-alt
  tile-mist-high: "#EEF3FA"    # surface-high (selector track, chips at rest)
  slate-border: "#E2E8F0"      # 1px card and input borders
  ink: "#0F172A"               # primary text
  ink-dim: "#475569"           # secondary text, section labels
  ink-more: "#64748B"          # supporting text, hints
  ink-faint: "#94A3B8"         # placeholder, chevrons, counts
  hairline: "rgba(37,99,235,0.10)"
  amber: "#D97706"             # warnings, partial-failure state
  red: "#DC2626"               # destructive (clear cache)
  green: "#059669"             # "Ready" model status
  # Dark mode
  dark-bg: "#0E1116"
  dark-surface: "#161B22"
  dark-surface-alt: "#1A2030"
  dark-surface-high: "#222A36"
  dark-border: "#1F2733"
  dark-title: "#60A5FA"
  dark-accent: "#3B82F6"
  dark-chip-text: "#93C5FD"
  dark-hairline: "rgba(96,165,250,0.12)"
  # Startup splash (dark)
  splash-top: "#0B1220"
  splash-bottom: "#050811"
  wave-navy: "#0B2545"
  wave-deep: "#1156CD"
  wave-blue: "#387DF4"
  wave-soft: "#7BABFF"
typography:
  app-title:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    letterSpacing: "-0.4px"
  title:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
  body:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
  body-small:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  section-label:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 700
    letterSpacing: "1px"
  badge:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 700
    letterSpacing: "0.2px"
rounded:
  hairline: "2px"
  sm: "8px"
  md: "10px"
  lg: "12px"
  tile: "14px"
  card: "16px"
  pill: "28px"
  full: "999px"
spacing:
  grid-gap: "6px"
  grid-edge: "10px"
  sm: "8px"
  md: "16px"
  lg: "24px"
components:
  search-pill:
    backgroundColor: "{colors.surface-white}"
    textColor: "{colors.ink-faint}"
    rounded: "{rounded.pill}"
    height: "56px"
  search-pill-send:
    backgroundColor: "{colors.cobalt}"
    textColor: "{colors.surface-white}"
    rounded: "{rounded.full}"
    size: "56px"
  photo-chip:
    backgroundColor: "{colors.cobalt-mist}"
    textColor: "{colors.cobalt-deep}"
    rounded: "{rounded.full}"
    typography: "{typography.badge}"
  suggestion-chip:
    backgroundColor: "{colors.surface-white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.full}"
    height: "36px"
  card:
    backgroundColor: "{colors.surface-white}"
    rounded: "{rounded.card}"
    padding: "14px 16px"
  photo-tile:
    backgroundColor: "{colors.tile-mist}"
    rounded: "{rounded.tile}"
  rank-badge:
    backgroundColor: "{colors.cobalt}"
    textColor: "{colors.surface-white}"
    rounded: "{rounded.full}"
    typography: "{typography.badge}"
  status-pill-ready:
    backgroundColor: "rgba(16,185,129,0.12)"
    textColor: "{colors.green}"
    rounded: "{rounded.full}"
  beta-pill:
    backgroundColor: "{colors.cobalt-mist}"
    textColor: "{colors.cobalt-deep}"
    rounded: "{rounded.full}"
    typography: "{typography.badge}"
  button-primary:
    backgroundColor: "{colors.cobalt}"
    textColor: "{colors.surface-white}"
    rounded: "{rounded.full}"
    height: "48px"
---

# Design System: KitaKo

> Extracted from the shipped Flutter code on `master` (Nov 2026). Source of
> truth: `apps/lib/src/ui/theme/palette.dart` (the `P` class, used by every
> screen), `apps/lib/main.dart` (ThemeData), and the screen files under
> `apps/lib/src/ui/screens/`. If this file and `palette.dart` disagree, the
> code wins. Update this file.

## Overview

**Creative North Star: "The Quiet Gallery"**

KitaKo is a camera roll you can talk to in Taglish. The interface stays out of
the way so the user's own photos supply the colour. The rest is a calm,
paper-sky canvas, white cards, slate text, and one cobalt accent that marks the
thing to do next: search, send, *Find Similar*, *Best match*. Density is high
where the user scans (a tight 6 px photo grid) and generous where the user
decides (56 px search pill, 16 px cards, roomy settings rows).

The personality is friendly and local, not technical. Copy speaks in short,
plain sentences ("Organizing your photos", "Picking up where we left off…").
Suggested queries are real Taglish phrases ("jeepney sa kalsada", "pamilya sa
hapag") and act as both onboarding and demo. Model names and algorithms show up
only in Settings, written as small secondary labels.

The one showpiece is the startup splash. It uses a deep navy gradient, animated
blue waves across the bottom 46%, and the logo scaling in elastically. It is
the only place the system raises its voice.

**Key Characteristics:**
- Single cobalt accent on a cool, near-white canvas; photos are the colour.
- Pill-shaped everything that is tappable (search, chips, badges, buttons).
- Rounded-square photo tiles (14 px) in a dense, pinch-resizable grid.
- Uppercase micro-labels with a 3 px cobalt tick as section headers.
- Shadows are rare and soft, tinted navy rather than black.
- Light mode by default; full dark mode; a hidden "girly-pop" theme.

## Colors

A cool, slate-and-cobalt palette that reads as trustworthy and quiet. Nearly
every hue is a Tailwind-family slate or blue, so it feels coherent.

### Primary
- **Cobalt** (#2563EB light / #3B82F6 dark): The only action colour. Search
  circle, send button, selected choice-card border, rank badges, section-label
  tick, filled buttons. Text and icons on cobalt are always white.
- **Cobalt Deep** (#1D4ED8): Chip and BETA-pill text, percentage readouts.
- **Cobalt Mist** (#DBEAFE light / rgba(59,130,246,0.18) dark): Soft fills
  behind cobalt icons (history bubbles, icon badges, query-header circle) and
  chip backgrounds.

### Neutral
- **Harbor Navy** (#0B2545): App-bar titles and headings in light mode. In dark
  mode titles switch to **Sky Title** (#60A5FA).
- **Paper Sky** (#F4F7FB): Scaffold and app-bar background (the app bar has no
  elevation and blends into the page).
- **Surface White** (#FFFFFF): Cards, search pill, bottom sheets.
- **Tile Mist** (#E2EAF4): Photo placeholders before thumbnails decode.
- **Slate Border** (#E2E8F0): 1 px borders on cards, chips, inputs.
- **Ink ladder**: #0F172A text → #475569 dim → #64748B more → #94A3B8 faint.
  Dark mode uses white at 100 / 78 / 55 / 38 % opacity.

### Semantic
- **Amber** (#D97706 / #F59E0B dark): Partial-failure banners ("Retry N /
  Skip"), the Force-top-results warning.
- **Red** (#DC2626 / #EF4444): Destructive actions only (Clear embedding cache).
- **Green** (#059669 / #10B981): "Ready" model status pill on a 12 % green tint.

### Named Rules
**The One Voice Rule.** Cobalt is the only saturated colour in the chrome. If
two things on screen are cobalt, the more important one is solid and the other
is a tint (Cobalt Mist).

**The Photos-Are-the-Palette Rule.** Never add decorative colour, gradients or
illustration to content screens. The user's photos are the colour; the chrome
stays slate.

### Known drift
`AppColors` (`app_theme.dart`) and `P` (`palette.dart`) swap `surfaceAlt` and
`surfaceHigh` in light mode (#EEF3FA vs #E2EAF4). Screens use `P`, so the values
in the frontmatter follow `P`. Remove `AppColors` or bring it in line with `P`.

## Typography

**Font:** Roboto (the Material 3 platform default on Android; SF Pro on iOS).
No custom font ships with the app.
**Icons:** Material Icons (outlined/rounded set, 13–24 px), usually cobalt
or ink-faint. Printed docs use Material Symbols Rounded as a close match.

**Character:** Neutral and native, so it feels like part of the phone. The
hierarchy comes from weight (500/600/700) and small size steps, not from a
display face.

### Hierarchy
- **App title** (700, 22 px, −0.4 tracking): "KitaKo", "Search", "Results",
  "Settings". Navy in light mode, sky blue in dark mode.
- **Title** (600, 15 px): Query header ("“beach sa umaga”"), filenames in
  Details, setting row labels.
- **Body** (500, 13–14 px): Recent queries, suggestion chips, list rows.
- **Body small** (400, 11–12 px): Row subtitles ("IVF-PQ · faster"), match
  counts ("24 matches · ranked by similarity"), metadata.
- **Section label** (700, 11 px, +1 tracking, UPPERCASE, Ink-dim): "SUGGESTED",
  "RECENT", "APPEARANCE", "MODELS", always after a 3×12 px cobalt tick.
- **Badge** (700, 10 px, +0.2 tracking): "★ Best match", "#2", "BETA".

**The Small-and-Sure Rule.** The size scale tops out at 22 px. Emphasis comes
from weight and colour, never from going bigger.

## Layout

- **Portrait only.** Orientation is locked in `main.dart`.
- **Gallery grid:** 3 columns by default, adjustable 2–6 by pinch or in
  Settings, persisted as `gallery_columns`. Gap 6 px, side padding 10 px,
  square tiles. Thumbnails decode with `cacheWidth: 256` only, never both width
  and height, so `BoxFit.cover` crops instead of stretching.
- **Date grouping:** Today → This week → This month → "Month YYYY" groups
  (newest first) → Earlier. Each group has an uppercase header plus a faint count.
- **Bottom-anchored search:** The search pill floats at the bottom of Home and
  Search, within thumb reach. It is the main entry point in the app.
- **Settings:** Grouped cards (16 px radius) under section labels (padding
  18 px top, 8 px bottom). Rows have a 32 px icon badge, label + subtitle, and a
  trailing control. Hairlines separate rows inside a card.
- **Rhythm:** 6 / 8 / 10 / 16 / 24 px. Cards pad 14–16 px.

## Elevation & Depth

Mostly flat and layered by tone: page (Paper Sky) → card (white + 1 px border)
→ tint (Cobalt Mist). Shadows are used sparingly and tinted navy (#0F2A4A),
never pure black, in light mode.

### Shadow Vocabulary
- **Floating pill** (`0 12px 32px rgba(15,42,74,0.10), 0 2px 4px rgba(15,42,74,0.06)`):
  Home search pill. In dark mode: black at 45 % / 30 %.
- **Header card** (`0 4px 12px rgba(15,42,74,0.06)`): Results query header.
- **Resting card** (`0 1px 3px rgba(15,42,74,0.04)`): Settings cards.
- **Focus ring** (`0 0 0 4px rgba(37,99,235,0.35)`): Active search field, drawn
  together with a 1.5 px cobalt border.

## Shapes

- **Pill (full / 28 px):** Search bar, chips, rank badges, status pills,
  primary buttons, the BETA tag. Anything tappable that is not a photo or a
  card is a pill.
- **Card (16 px):** Settings groups, Recent list, query header, bottom sheets.
- **Tile (14 px):** Photo thumbnails in every grid.
- **Control (8–12 px):** Choice cards, column selector, input fields, snackbars
  (10 px).
- **Tick (2 px):** The 3 px section-label bar and progress tracks.

## Components

- **Search pill (Home).** 56 px tall, white, 1 px border, floating shadow.
  Left: 36 px cobalt circle with a white search icon. Middle: the last query
  under a cobalt "RECENT" micro-label, or the hint *"Search photos in
  Taglish…"*. Right: a "Photo" chip (image icon). Tapping anywhere opens
  Search, which slides up from the bottom.
- **Search field (Search).** Same pill with a 1.5 px cobalt border and a 4 px
  focus ring, a clear (×) button, and an inline Photo chip. A separate 56 px
  solid cobalt circle holds the send icon.
- **Suggestion chip.** 36 px, white, bordered pill, a cobalt `auto_awesome`
  sparkle (13 px) and 13 px/500 text. The set is drawn at random from 50 Taglish
  phrases.
- **Recent row.** Inside a 16 px card: cobalt history icon in a Cobalt Mist
  circle, query (14/500), `north_east` arrow, and a remove (×) button.
- **Photo tile.** 14 px radius, Tile Mist placeholder. On Results it adds a
  top-left rank badge (★ Best match / #2 / #3…) and, except on the best match,
  a bottom-right strength meter: a dark pill with three bars (6/9/12 px), filled
  in cobalt. **No numeric scores on tiles.**
- **Filter sheet.** Modal bottom sheet with "Date Range" (From/Until date pills
  with a calendar icon), "Relevance" (Off / Low 20 % / Medium 45 % / High 70 %)
  and a full-width "Apply Filters" button; "Reset" sits top right. Active
  filters show as a dismissible summary strip.
- **Choice card (Settings → Search mode).** Two side-by-side cards,
  Performance (IVF-PQ · faster) and Accuracy (HNSW · higher recall). The
  selected card gets a 1.5 px cobalt border.
- **Status pill.** "● Ready" in green on a 12 % green tint; "Missing" otherwise.
- **Startup splash.** Navy gradient (#0B1220 → #050811) in dark mode, white in
  light mode, animated waves, 180 px logo at 40 px radius, ring spinner, a
  friendly status line, a 200×4 px progress bar and a percentage readout.
  Failure states turn into a status card with pill buttons (Retry / Browse /
  Skip).
- **Hidden theme: "girly-pop".** Toggling Dark mode 15 times quickly repaints
  every token rose (#F7C8DC canvas, wine #500724 text, white accent) and shows
  a 💅 overlay. With 6 gallery columns set, one more dark-mode tap switches it
  off. `P` handles it, so screens never branch on it.

### Motion
Short and functional: 120 ms for selection changes (column picker, chips),
150–350 ms ease-in-out for page and sheet transitions (Search slides up from
the bottom). The only expressive motion is the splash (elastic logo, 600–900 ms
waves).

## Do's and Don'ts

**Do**
- Read every colour from `P.*(isDark)`. Never hard-code a hex in a screen.
- Use a pill for anything tappable, 14 px for photos, 16 px for cards.
- Head every content group with the uppercase label + cobalt tick.
- Use friendly, plain-language status copy; keep model and algorithm names in
  Settings subtitles.
- Show similarity as rank and a 3-bar meter, never as a raw score.

**Don't**
- Don't add a second accent colour or decorative gradients outside the splash.
- Don't use black shadows in light mode; tint them navy (#0F2A4A).
- Don't set both `cacheWidth` and `cacheHeight` on thumbnails.
- Don't go above 22 px type or add a display font.
- Don't use red for anything that isn't destructive.
