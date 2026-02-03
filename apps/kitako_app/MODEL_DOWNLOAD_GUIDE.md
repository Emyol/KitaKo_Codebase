# Model Download Guide

## Overview

The KitaKo app now supports two model options with different quality/size tradeoffs:

| Model | Size | Quality | Download Method |
|-------|------|---------|----------------|
| **SigLIP-1 (Quantized)** | ~210 MB | Good | Auto-download from HuggingFace |
| **SigLIP-2 (FP32)** | ~1.5 GB | Best | Manual setup (recommended) |

## SigLIP-1 (Quantized) - Quick Start

**Best for:** Fast setup, limited storage, good enough quality

### Auto-Download Steps:
1. Launch the app
2. On the model download screen, tap **"Download SigLIP-1"**
3. Wait for download to complete (~210 MB)
4. Models will be automatically cached

The app downloads from HuggingFace: `Xenova/siglip-base-patch16-224`

## SigLIP-2 (FP32) - Best Quality ⭐ RECOMMENDED

**Best for:** Best search accuracy, proper embedding alignment

### Why SigLIP-2?
- ✅ Includes projection layers for proper vision/text alignment
- ✅ Full precision (FP32) - no quantization loss
- ✅ Larger vocabulary (256K tokens vs 32K)
- ✅ Higher resolution (256×256 vs 224×224)
- ✅ Better multilingual support
- ❌ Large download size (1.5GB)

### Manual Setup Steps:

#### Method 1: ADB Push (Recommended)

1. **Locate the models in your workspace:**
   ```
   C:\Users\Jhezra\Documents\KitaKo_System\assets\models\
   ├── siglip2_vision_model_fp32.onnx  (371 MB)
   └── siglip2_text_model_fp32.onnx    (1.1 GB)
   ```

2. **Push to device using ADB:**
   ```bash
   cd C:\Users\Jhezra\Documents\KitaKo_System\assets\models
   adb -s IV5XLBPN59BQXOWW push siglip2_vision_model_fp32.onnx /data/local/tmp/
   adb -s IV5XLBPN59BQXOWW push siglip2_text_model_fp32.onnx /data/local/tmp/
   ```

3. **Restart the app**
   - The app will automatically detect and copy models from `/data/local/tmp/`
   - Models will be moved to the app's cache directory
   - Look for log messages: `ModelDownloadService: Copying siglip2_vision from tmp...`

#### Method 2: Direct Copy (If you have file access)

If you can access the device's file system directly:

1. Get the app's cache directory path (shown in startup logs):
   ```
   Model cache directory: /data/user/0/com.example.kitako_app/app_flutter/onnx_models
   ```

2. Copy models directly:
   ```bash
   adb -s IV5XLBPN59BQXOWW push siglip2_vision_model_fp32.onnx /data/user/0/com.example.kitako_app/app_flutter/onnx_models/
   adb -s IV5XLBPN59BQXOWW push siglip2_text_model_fp32.onnx /data/user/0/com.example.kitako_app/app_flutter/onnx_models/
   ```

3. Restart the app

## Verification

### Check Logs on Startup

**SigLIP-2 successfully loaded:**
```
EmbeddingService: Checking for downloaded SigLIP-2...
EmbeddingService: Loading SigLIP-2 from:
  Vision: /data/user/0/.../siglip2_vision_model_fp32.onnx
  Text: /data/user/0/.../siglip2_text_model_fp32.onnx
EmbeddingService: SigLIP-2 initialized successfully
EmbeddingService: ✅ Using SigLIP-2 (256x256, 256K vocab, with projection) - DOWNLOADED
```

**Falling back to SigLIP-1:**
```
EmbeddingService: SigLIP-2 models not available (vision: false, text: false)
EmbeddingService: Vision encoder ready: true
EmbeddingService: ✅ Using ONNX (SigLIP-1 quantized)
```

## Testing Search Quality

After setup, test with:
- Search: "billiards" - Should show pool/billiard images with distances < 1.0
- Search: "basketball" - Should show basketball images with distances < 1.0

### Expected Results

**With SigLIP-2 (proper alignment):**
- Distances: 0.3 - 0.9 (well aligned)
- Relevant results in top positions
- Clear separation between relevant and irrelevant

**With SigLIP-1 (no projection layers):**
- Distances: 2.0 - 2.3 (misaligned)
- Results may be less accurate
- Less clear separation

## Troubleshooting

### Models not copying from /data/local/tmp/

**Check file permissions:**
```bash
adb -s IV5XLBPN59BQXOWW shell ls -l /data/local/tmp/*.onnx
```

**Verify file sizes:**
```bash
adb -s IV5XLBPN59BQXOWW shell du -h /data/local/tmp/*.onnx
```

Should show:
- siglip2_vision_model_fp32.onnx: ~371 MB
- siglip2_text_model_fp32.onnx: ~1.1 GB

### App still using mock mode

1. Check if models are accessible:
   ```bash
   adb -s IV5XLBPN59BQXOWW shell ls /data/user/0/com.example.kitako_app/app_flutter/onnx_models/
   ```

2. Clear app data and restart:
   ```bash
   adb -s IV5XLBPN59BQXOWW shell pm clear com.example.kitako_app
   ```

3. Re-push models and restart

## Storage Requirements

- **SigLIP-1**: ~210 MB cache space
- **SigLIP-2**: ~1.5 GB cache space
- Both models can coexist (app uses SigLIP-2 if available)

## UI Features

The model download screen now shows:

1. **Model Quality Chooser**
   - Two cards: SigLIP-1 vs SigLIP-2
   - Size comparison
   - Quality indicators
   - "RECOMMENDED" badge on SigLIP-2

2. **Download Progress**
   - Live progress bars
   - Current model being downloaded
   - Download speed estimate

3. **Manual Setup Instructions**
   - Tap "Setup SigLIP-2 (Manual)" for step-by-step guide
   - Copy-paste friendly ADB commands
   - File location paths

4. **Demo Mode Option**
   - Continue without models for testing UI
   - Uses mock embeddings (random vectors)

## Developer Notes

### Code Changes

- `model_download_service.dart`: Added SigLIP-2 model definitions
- `embedding_service.dart`: Priority check for downloaded SigLIP-2
- `model_download_gate.dart`: Enhanced UI with manual setup instructions

### Model Priority

The app initializes in this order:
1. ✅ SigLIP-2 (downloaded)
2. ⚠️ SigLIP-2 (assets) - removed, too large
3. ⚠️ ONNX SigLIP-1 (downloaded)
4. ⚠️ TFLite (if available)
5. ❌ Mock mode

### Future Improvements

- [ ] Resume partial downloads
- [ ] Model auto-updates
- [ ] Compression/streaming for SigLIP-2
- [ ] Cloud storage integration (Google Drive, Dropbox)
- [ ] P2P model sharing between devices
