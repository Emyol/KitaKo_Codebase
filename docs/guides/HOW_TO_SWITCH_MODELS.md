# 🎯 How to Switch to SigLIP-2 (Configuration Only)

Since runtime toggling requires re-indexing the entire gallery, here's how to **configure which model to use at startup**.

---

## ✅ Simple Switch: Use SigLIP-2 by Default

### Location: `apps/kitako_app/lib/src/services/embedding_service.dart`

### Change 1: Update `initialize()` method (Line ~116-131)

**Current code:**
```dart
Future<bool> initialize() async {
  if (_isInitialized) return true;

  // Try ONNX backend first (if models are available)
  if (await _tryInitializeOnnx()) {
    _activeBackend = EmbeddingBackend.onnx;
    _isInitialized = true;
    debugPrint('EmbeddingService: Initialized with ONNX backend');
    return true;
  }

  // Try TFLite backend
  if (await _tryInitializeTflite()) {
    _activeBackend = EmbeddingBackend.tflite;
    _isInitialized = true;
    debugPrint('EmbeddingService: Initialized with TFLite backend');
    return true;
  }

  // Fall back to mock mode
  _activeBackend = EmbeddingBackend.mock;
  _isInitialized = true;
  debugPrint('EmbeddingService: Running in MOCK mode');
  return true;
}
```

**Change to:**
```dart
Future<bool> initialize() async {
  if (_isInitialized) return true;

  // 🔥 USE SIGLIP-2 DIRECTLY FROM ASSETS
  if (await initializeWithSiglip2()) {
    return true;
  }

  // Fallback: Try ONNX backend (SigLIP-1 downloaded models)
  if (await _tryInitializeOnnx()) {
    _activeBackend = EmbeddingBackend.onnx;
    _isInitialized = true;
    debugPrint('EmbeddingService: Initialized with ONNX backend (SigLIP-1)');
    return true;
  }

  // Try TFLite backend
  if (await _tryInitializeTflite()) {
    _activeBackend = EmbeddingBackend.tflite;
    _isInitialized = true;
    debugPrint('EmbeddingService: Initialized with TFLite backend');
    return true;
  }

  // Fall back to mock mode
  _activeBackend = EmbeddingBackend.mock;
  _isInitialized = true;
  debugPrint('EmbeddingService: Running in MOCK mode');
  return true;
}
```

---

## 📝 That's It!

**One line change:** Just call `initializeWithSiglip2()` first in the `initialize()` method.

### What This Does:
- ✅ Loads SigLIP-2 models from `assets/models/` on startup
- ✅ Uses 256×256 image size
- ✅ Uses 256K vocabulary tokenizer
- ✅ No runtime switching needed
- ✅ All images indexed with SigLIP-2 from the start

### To Switch Back to SigLIP-1:
Just remove that line and it falls back to the original behavior (downloaded ONNX models or TFLite).

---

## 🔄 Alternative: Configuration Constant

If you want to make it even more explicit, add a constant at the top of the file:

```dart
// At the top of embedding_service.dart (around line 40)
class EmbeddingService {
  /// Model version to use (change this to switch models)
  static const SiglipModelVersion defaultModelVersion = SiglipModelVersion.siglip2;
  
  // ... rest of the class
}
```

Then in `initialize()`:
```dart
Future<bool> initialize() async {
  if (_isInitialized) return true;

  // Use configured model version
  if (defaultModelVersion == SiglipModelVersion.siglip2) {
    if (await initializeWithSiglip2()) {
      return true;
    }
  }
  
  // Original fallback logic
  if (await _tryInitializeOnnx()) {
    // ...
  }
  // ...
}
```

---

## 📊 Model Comparison Quick Reference

| Model | Change `defaultModelVersion` to: |
|-------|----------------------------------|
| **SigLIP-1** | `SiglipModelVersion.siglip1` (or remove the check) |
| **SigLIP-2** | `SiglipModelVersion.siglip2` |

---

## 🎯 Summary

**Single location to change:**
- File: `apps/kitako_app/lib/src/services/embedding_service.dart`
- Method: `initialize()` (around line 116)
- Change: Call `initializeWithSiglip2()` first

**That's it!** No UI changes, no runtime toggling, no re-indexing complications. Just pick the model at compile time.
