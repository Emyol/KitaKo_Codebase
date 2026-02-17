# KitaKo iOS Testing Guide

> **Last Updated:** February 17, 2026
> **Branch:** `feat/siglip1-aligned-embeddings`
> **Target Platform:** iOS 13.0+

---

## Prerequisites

Before you start, make sure you have all of the following installed on your **Mac**:

| Requirement | Minimum Version | How to Check |
|---|---|---|
| **macOS** | Ventura 13+ (recommended) | Apple menu → About This Mac |
| **Xcode** | 15.0+ | `xcode-select --version` |
| **Flutter SDK** | 3.10.4+ | `flutter --version` |
| **Dart SDK** | 3.10.4+ | `dart --version` |
| **CocoaPods** | 1.14+ | `pod --version` |
| **Apple Developer Account** | Free or paid | Required for physical device testing |

### Install Flutter (if needed)
```bash
# Follow: https://docs.flutter.dev/get-started/install/macos
# After install, verify:
flutter doctor
```

Make sure `flutter doctor` shows no issues for iOS development (Xcode, CocoaPods, etc.).

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/Emyol/KitaKo_Codebase.git
cd KitaKo_Codebase
git checkout feat/siglip1-aligned-embeddings
```

---

## Step 2: Download Model Files from Google Drive

The ML models are **not included in the repository** (they are too large for Git). You need to download them from our shared Google Drive.

### Required Models (Pick ONE set)

#### Option A: SigLIP-1 Quantized (Recommended for Testing — ~210 MB total)

These are the **smallest models** and will auto-download on first launch if you have an internet connection. **You can skip this step** and let the app download them automatically.

If you prefer to download manually or don't have reliable internet on the test device:

| File | Size | Google Drive Folder |
|---|---|---|
| `vision_model_quantized.onnx` | ~99.5 MB | `Models/SigLIP-1/quantized/` |
| `text_model_quantized.onnx` | ~111 MB | `Models/SigLIP-1/quantized/` |

#### Option B: SigLIP-1 Aligned (Best Accuracy — ~775 MB total)

| File | Size | Google Drive Folder |
|---|---|---|
| `siglip_vision_aligned_full.onnx` | ~354 MB | `Models/SigLIP-1/aligned/` |
| `siglip_text_aligned_full.onnx` | ~421 MB | `Models/SigLIP-1/aligned/` |

#### Option C: Fine-tuned SigLIP (Taglish-Trained — ~1.4 GB total)

| File | Size | Google Drive Folder |
|---|---|---|
| `finetuned_vision_model_fp32.onnx` | ~354 MB | `Models/finetuned/` |
| `finetuned_text_model_fp32.onnx` | ~1,077 MB | `Models/finetuned/` |

#### Option D: SigLIP-2 FP32 (Largest — ~1.5 GB total)

| File | Size | Google Drive Folder |
|---|---|---|
| `siglip2_vision_model_fp32.onnx` | ~371 MB | `Models/SigLIP-2/` |
| `siglip2_text_model_fp32.onnx` | ~1,129 MB | `Models/SigLIP-2/` |

> **Recommendation:** Start with **Option A** (auto-download) for a quick test run. If you want better search accuracy, use **Option B** or **Option C**.

---

## Step 3: Install Dependencies

```bash
cd apps/kitako_app
flutter pub get
```

Then install iOS CocoaPods:

```bash
cd ios
pod install
cd ..
```

> If `pod install` fails, try:
> ```bash
> pod repo update
> pod install --repo-update
> ```

---

## Step 4: Transfer Models to iOS Device

### If Using Option A (Auto-Download)

**No manual transfer needed.** The app will download the SigLIP-1 Quantized models (~210 MB) automatically on first launch. Just make sure the device has a **Wi-Fi connection**.

### If Using Option B, C, or D (Manual Models)

On iOS, you cannot use `adb push` like Android. Instead, use one of these methods:

#### Method 1: Finder / iTunes File Sharing (Recommended)

1. **Build and install the app first** (see Step 5)
2. Connect your iPhone to your Mac via USB cable
3. Open **Finder** (macOS Catalina+) or **iTunes** (older macOS)
4. Select your iPhone in the sidebar
5. Go to the **Files** tab
6. Find **Kitako App** in the app list
7. Drag and drop the `.onnx` model files into the app's Documents folder
8. The files will be placed in the app sandbox at `Documents/`

> **Important:** After dropping the files, you need to move them into the correct subdirectory. The app expects models in `Documents/onnx_models/`. You can do this with a helper script or by restarting the app (it will check `Documents/` on startup).

#### Method 2: Xcode Device File Transfer

1. Open **Xcode** → **Window** → **Devices and Simulators**
2. Select your connected iPhone
3. Find **kitako_app** in the installed apps list
4. Click the **gear icon** (⚙️) → **Download Container...**
5. This downloads the app sandbox. Add the models to `AppData/Documents/onnx_models/`
6. Then click ⚙️ → **Replace Container...** to upload the modified sandbox back

The model files should be placed so the final paths look like:

```
<App Sandbox>/Documents/onnx_models/
├── vision_model_quantized.onnx        (Option A)
├── text_model_quantized.onnx          (Option A)
├── siglip_vision_aligned_full.onnx    (Option B)
├── siglip_text_aligned_full.onnx      (Option B)
├── finetuned_vision_model_fp32.onnx   (Option C)
├── finetuned_text_model_fp32.onnx     (Option C)
├── siglip2_vision_model_fp32.onnx     (Option D)
└── siglip2_text_model_fp32.onnx       (Option D)
```

#### Method 3: iOS Simulator (No Physical Device)

If testing on the iOS Simulator, you can copy models directly into the simulator's file system:

```bash
# Find your simulator's app Documents directory
DOCS_DIR=$(xcrun simctl get_app_container booted com.example.kitakoApp data)/Documents/onnx_models

# Create the directory
mkdir -p "$DOCS_DIR"

# Copy the model files
cp /path/to/downloaded/vision_model_quantized.onnx "$DOCS_DIR/"
cp /path/to/downloaded/text_model_quantized.onnx "$DOCS_DIR/"
```

> **Note:** The bundle identifier may differ. Run `xcrun simctl listapps booted` to find the correct one after installing the app.

---

## Step 5: Build and Run

### On iOS Simulator

```bash
cd apps/kitako_app

# List available simulators
flutter devices

# Run on a simulator (e.g., iPhone 15 Pro)
flutter run -d "iPhone 15 Pro"
```

### On Physical iPhone

1. Open `apps/kitako_app/ios/Runner.xcworkspace` in Xcode
2. Select your **Team** under **Signing & Capabilities** (Runner target)
3. Connect your iPhone via USB
4. Select your iPhone as the build target
5. Click **Run** (▶) or from terminal:

```bash
flutter run -d <your-device-id>
# Get device ID with: flutter devices
```

> **First time on physical device:** You may need to trust the developer certificate on the iPhone:
> **Settings → General → VPN & Device Management → Developer App → Trust**

---

## Step 6: What to Expect on First Launch

1. **Model Download Gate** — If no models are found on the device:
   - With internet: The app will offer to **auto-download SigLIP-1 Quantized** (~210 MB). Tap **Download** and wait.
   - Without internet: Tap **"Continue without models (Demo Mode)"** to run with mock embeddings (search results will be random).

2. **Splash Screen** — Animated KitaKo logo (3 seconds)

3. **Home Screen** — Gallery grid showing your indexed photos
   - The app will request **photo library access**. Tap **Allow Access to All Photos**.
   - It will begin indexing up to 1,000 of your photos (may take 1-3 minutes depending on model and device).

4. **Ready to Search** — Tap the search bar at the bottom to enter queries.

---

## Step 7: Testing Checklist

### Core Functionality

| # | Test | Expected Result | Status |
|---|---|---|---|
| 1 | App launches without crash | Splash screen → Home screen | ☐ |
| 2 | Photo permission granted | Gallery photos appear in home grid | ☐ |
| 3 | Model download completes (Option A) | Progress bar fills, no errors | ☐ |
| 4 | Image indexing completes | Photos load in the home grid | ☐ |
| 5 | Text search: `"dog"` | Returns results (may vary in relevance) | ☐ |
| 6 | Text search: `"red dress"` | Returns results | ☐ |
| 7 | Taglish search: `"kumakain sa beach"` | Returns results + shows normalized query | ☐ |
| 8 | Image-to-image search | Select photo → similar images returned | ☐ |
| 9 | Tap a result → Details screen | Full-size image, metadata, share button | ☐ |
| 10 | Share button works | System share sheet appears | ☐ |
| 11 | Dark mode toggle | Settings → toggle → theme changes | ☐ |
| 12 | Demo mode (no models) | App runs, search returns mock results | ☐ |

### Performance

| # | Test | Expected Range |
|---|---|---|
| 1 | Time to index 100 photos | 30s – 2 min (depends on model + device) |
| 2 | Search response time | < 3 seconds for text query |
| 3 | Memory usage during indexing | < 500 MB |
| 4 | App size (installed) | ~150-250 MB (without large models) |

### Edge Cases

| # | Test | Expected Result |
|---|---|---|
| 1 | Search with empty query | No crash, shows all images or no-op |
| 2 | Search with very long text | Truncated to 64 tokens, no crash |
| 3 | No photos on device | Shows empty state or mock images |
| 4 | Airplane mode + no cached models | Demo mode available |
| 5 | Rotate device | App stays in portrait |

---

## Troubleshooting

### `pod install` fails

```bash
# Update CocoaPods repo
pod repo update

# Clean and retry
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
```

### Xcode signing error

- Open `Runner.xcworkspace` in Xcode
- Go to **Runner** target → **Signing & Capabilities**
- Select your **Team** (personal or organization Apple ID)
- Change **Bundle Identifier** to something unique if needed (e.g., `com.yourname.kitakoApp`)

### App crashes on photo access

The `Info.plist` has been updated with the required permission keys. If you still see crashes:
- Check that `NSPhotoLibraryUsageDescription` exists in `ios/Runner/Info.plist`
- Clean build: `flutter clean && flutter pub get && cd ios && pod install && cd ..`

### Models not detected after file transfer

The app looks for models in `Documents/onnx_models/`. Verify:
1. The filenames match **exactly** (case-sensitive)
2. Files are in the `onnx_models/` subdirectory, not just `Documents/`
3. File sizes match the expected sizes (±5%):
   - `vision_model_quantized.onnx` → ~99.5 MB
   - `text_model_quantized.onnx` → ~111 MB

### ONNX Runtime crash or slow inference

- SigLIP-1 Quantized is the fastest and most memory-efficient option
- Older iPhones (iPhone X or earlier) may struggle with FP32 models
- If inference crashes, try the quantized models instead of FP32

### Build error: minimum iOS version

If you see deployment target errors, set the minimum iOS version in `ios/Podfile`:
```ruby
platform :ios, '13.0'
```

---

## Model Priority Reference

The app tries models in this order and uses the first one that loads:

| Priority | Model | How to Get It |
|---|---|---|
| 1 | Fine-tuned SigLIP | Download from Drive → transfer to device |
| 2 | SigLIP-1 Aligned | Download from Drive → transfer to device |
| 3 | SigLIP-2 FP32 (downloaded) | Download from Drive → transfer to device |
| 4 | SigLIP-2 FP32 (assets) | Bundled if added to assets dir (not default) |
| 5 | SigLIP-1 Quantized | **Auto-downloads** on first launch (~210 MB) |
| 6 | TFLite (legacy) | Bundled in app assets |
| 7 | Mock mode | Always available, returns random results |

---

## Quick Summary

For the **fastest path to a working test**:

1. Clone the repo, checkout `feat/siglip1-aligned-embeddings`
2. `cd apps/kitako_app && flutter pub get && cd ios && pod install && cd ..`
3. `flutter run -d <your-device>`
4. Grant photo access when prompted
5. Let the app auto-download SigLIP-1 Quantized models (~210 MB over Wi-Fi)
6. Wait for image indexing to complete
7. Start searching!
