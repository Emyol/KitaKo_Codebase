# SigLIP-2 Quick Reference Card

## 🚀 Quick Start

### Initialize with SigLIP-2
```dart
await embeddingService.initializeWithSiglip2();
```

### Switch Models at Runtime
```dart
// To SigLIP-2
await embeddingService.switchToModel(SiglipModelVersion.siglip2);

// To SigLIP-1
await embeddingService.switchToModel(SiglipModelVersion.siglip1);
```

### Check Current Model
```dart
print('Model: ${embeddingService.modelVersion.name}');
print('Config: ${embeddingService.modelConfig}');
```

## 📊 Model Comparison

| Feature | SigLIP-1 | SigLIP-2 |
|---------|----------|----------|
| **Image Size** | 224×224 | 256×256 |
| **Vocabulary** | 32K | 256K |
| **Projection** | ❌ No | ✅ Yes |
| **Speed** | ⚡ Faster | 🐢 Slower |
| **Accuracy** | 👍 Good | 🌟 Better |
| **File Location** | Downloaded | Assets |

## 🎯 Expected Results

### Good Match (SigLIP-2)
- Cosine similarity: **> 0.3**
- Distance: **< 1.0**
- Example: Query "cat" → cat images

### Poor Match
- Cosine similarity: **< 0.1**  
- Distance: **> 1.5**
- Example: Query "cat" → random images

### Current Issue (Before Fix)
- Distance: **~2.0** (orthogonal/random)
- Means: **embeddings not aligned**

## 🔧 Key Files

### Core Implementation
- `packages/kitako_embedding/lib/src/siglip_model_config.dart`
- `packages/kitako_embedding/lib/src/onnx_siglip_inference.dart`
- `apps/kitako_app/lib/src/services/embedding_service.dart`

### UI Component
- `apps/kitako_app/lib/src/widgets/model_version_toggle.dart`

### Tests
- `packages/kitako_embedding/test/siglip_model_config_test.dart`

### Documentation
- `SIGLIP2_TOGGLE_GUIDE.md` - Detailed usage guide
- `SIGLIP2_IMPLEMENTATION_SUMMARY.md` - Full implementation details

## 📁 Asset Paths

```dart
// SigLIP-2 models (FP32)
assets/models/siglip2_vision_model_fp32.onnx  // ✅ Present
assets/models/siglip2_text_model_fp32.onnx    // ✅ Present
assets/tokenizer/tokenizer.json               // ✅ Present
```

## 🧪 Testing Commands

### Run Config Tests
```bash
cd packages/kitako_embedding
flutter test test/siglip_model_config_test.dart
```

### Test Search with SigLIP-2
```dart
// In your app
await embeddingService.switchToModel(SiglipModelVersion.siglip2);
final results = await searchService.search('billiards');
// Check if results are more relevant
```

## 🐛 Troubleshooting

### Check Output Tensor Names
**Look for this in logs:**
```
OnnxSiglipInference: Vision model output names: [...]
OnnxSiglipInference: Text model output names: [...]
```

**If names differ, update config:**
```dart
// In siglip_model_config.dart line 95-96
visionOutputTensorName: 'actual_name',
textOutputTensorName: 'actual_name',
```

### Verify Embeddings
```dart
final embedding = await embeddingService.generateEmbedding('test');
print('Length: ${embedding.length}');  // Should be 768
```

### Check Model Loading
```dart
if (embeddingService.isTextReady && embeddingService.isImageReady) {
  print('✅ Both encoders ready');
} else {
  print('❌ Model loading failed');
}
```

## 🎨 UI Integration

### Add Toggle to Settings
```dart
import 'package:kitako_app/src/widgets/model_version_toggle.dart';

// In your settings screen
ModelVersionToggle(embeddingService: embeddingService)
```

### Custom Toggle
```dart
SegmentedButton<SiglipModelVersion>(
  segments: [
    ButtonSegment(value: SiglipModelVersion.siglip1, label: Text('v1')),
    ButtonSegment(value: SiglipModelVersion.siglip2, label: Text('v2')),
  ],
  selected: {embeddingService.modelVersion},
  onSelectionChanged: (selected) async {
    await embeddingService.switchToModel(selected.first);
  },
);
```

## 💡 Pro Tips

1. **Clear cache after switching** - Already handled automatically
2. **Test on real device** - Mobile performance may differ
3. **Monitor memory usage** - FP32 models are large
4. **Use thumbnails** - Already implemented for speed
5. **Check logs** - Verbose logging enabled for debugging

## ⚡ Performance Expectations

### SigLIP-1 (Faster)
- Embedding time: ~50-100ms per image
- Good for real-time search
- Lower accuracy

### SigLIP-2 (Better)
- Embedding time: ~80-150ms per image  
- 30% slower due to larger images
- Higher accuracy

## 🎯 Success Criteria

Your implementation is working when:
- ✅ Both models load without errors
- ✅ Can switch between models at runtime
- ✅ SigLIP-2 shows lower distances for matches
- ✅ SigLIP-2 returns more relevant results
- ✅ Distances are < 1.0 (not ~2.0) for matches

## 📞 Quick Commands

```bash
# Run tests
flutter test packages/kitako_embedding/test/

# Check for errors
flutter analyze

# Build and run on device
flutter run -d <device-id>

# Hot reload (after code changes)
# Press 'r' in terminal
```

## 🔗 Related Issues

**Current Problem:** Embeddings not aligned (distance ~2.0)
**Root Cause:** Missing projection layers OR tokenizer mismatch
**Solution:** SigLIP-2 has projection layers built-in

**Expected Fix:** Distances should drop from ~2.0 to <1.0 for good matches

---

*Quick Reference - Keep this handy! 📌*
