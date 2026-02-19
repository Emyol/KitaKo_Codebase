# SigLIP Model Integration Testing

## Quick Start - Run on Android Emulator

```powershell
# 1. Make sure emulator is running
flutter emulators --launch <emulator-name>

# 2. Run the integration test
cd apps\kitako_app
flutter test integration_test/siglip_model_test.dart

# Or with more verbose output
flutter test integration_test/siglip_model_test.dart --verbose
```

## What This Test Does

This integration test validates the critical difference between SigLIP-1 and SigLIP-2 models by measuring **cross-modal similarity** (how well image and text embeddings align).

### Expected Results

**SigLIP-1 ALIGNED** (FP32, with projection):
- Cross-modal similarity: **0.50 - 0.75**
- These models have projection layers and should work reasonably well

**SigLIP-2** (FP32, with improved projection):
- Cross-modal similarity: **0.75 - 0.95**
- Should show significant improvement over SigLIP-1

### What the Numbers Mean

- **< 0.3**: Wrong models or broken projection layers ❌
- **0.3 - 0.5**: Weak alignment, models may work but not optimal ⚠️
- **0.5 - 0.7**: Decent alignment, models will work ✓
- **0.7 - 0.95**: Strong alignment, projection layers working correctly ✓✓

## Prerequisites

### 1. Models Must Be on Device

Make sure you've deployed the models using the setup script:

```powershell
# Deploy SigLIP-2 models
cd apps\kitako_app
.\setup_siglip2.ps1
```

Or manually:
```bash
# SigLIP-2 models
adb push <workspace>/assets/models/siglip2_vision_model_fp32.onnx /data/local/tmp/
adb push <workspace>/assets/models/siglip2_text_model_fp32.onnx /data/local/tmp/
adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip2_vision_model_fp32.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/
adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip2_text_model_fp32.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/

# SigLIP-1 ALIGNED models (if not already present)
adb push <workspace>/assets/models/onnx/siglip_vision_aligned_full.onnx /data/local/tmp/
adb push <workspace>/assets/models/onnx/siglip_text_aligned_full.onnx /data/local/tmp/
adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip_vision_aligned_full.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/
adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip_text_aligned_full.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/
```

### 2. Add Integration Test Dependency

Make sure `pubspec.yaml` has:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

## Troubleshooting

### Test Fails to Initialize Models

**Error**: `Failed to load vision encoder: File doesn't exist`

**Solution**: Models aren't on device. Run the setup script or push them manually.

### Similarity Too Low (< 0.3)

**Possible causes**:
1. Wrong models deployed (e.g., non-projection versions)
2. Models corrupted during transfer
3. Model version mismatch

**Solution**: Re-deploy models from original source

### Out of Memory

**Solution**: Close other apps on the emulator or use a device with more RAM

## Sample Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL TEST: Cross-Modal Similarity Comparison
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ SigLIP-1 ALIGNED initialized
✓ SigLIP-2 initialized

Generating embeddings...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SigLIP-1 ALIGNED: 0.6234
SigLIP-2: 0.8745
Improvement: 40.3%

✓ GOOD: SigLIP-1 ALIGNED has reasonable similarity
✓ EXCELLENT: SigLIP-2 has HIGH similarity
  (Projection layers are working correctly!)
✓ SigLIP-2 is better than SigLIP-1 ALIGNED

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Next Steps After Testing

If tests pass:
1. ✅ Models are correctly configured
2. ✅ Projection layers are working
3. ✅ Ready to use in production

Update your app to use SigLIP-2 for better search quality!
