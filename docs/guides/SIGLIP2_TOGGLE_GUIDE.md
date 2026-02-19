# SigLIP Model Toggle Guide

## Overview

The KitaKo system now supports switching between SigLIP-1 and SigLIP-2 model versions. SigLIP-2 provides improved multilingual support and better semantic understanding.

## Model Differences

| Feature | SigLIP-1 | SigLIP-2 |
|---------|----------|----------|
| **Image Size** | 224x224 | 256x256 |
| **Vocabulary** | ~32,000 tokens | ~256,000 tokens |
| **Projection Layer** | No | Yes |
| **Multilingual Support** | Basic | Enhanced |
| **Model Files** | Downloaded from Xenova | Bundled in assets |

## Usage

### Initialize with SigLIP-2

```dart
final embeddingService = EmbeddingService();

// Option 1: Initialize with SigLIP-2 from assets
await embeddingService.initializeWithSiglip2();

// Option 2: Switch to SigLIP-2 after initialization
await embeddingService.switchToModel(SiglipModelVersion.siglip2);
```

### Switch Between Models

```dart
// Switch to SigLIP-2
await embeddingService.switchToModel(SiglipModelVersion.siglip2);

// Switch back to SigLIP-1
await embeddingService.switchToModel(SiglipModelVersion.siglip1);

// Check current model
print('Current model: ${embeddingService.modelVersion.name}');
print('Config: ${embeddingService.modelConfig}');
```

### Check Model Status

```dart
// Get current configuration
final config = embeddingService.modelConfig;
if (config != null) {
  print('Image size: ${config.imageSize}x${config.imageSize}');
  print('Vocabulary: ${config.vocabularySize}');
  print('Has projection: ${config.hasProjectionLayer}');
}
```

## Asset Files

SigLIP-2 models are located in:
- Vision: `assets/models/siglip2_vision_model_fp32.onnx`
- Text: `assets/models/siglip2_text_model_fp32.onnx`

These files should be present in the `assets/models/` directory.

## Configuration

### SigLIP-1 Configuration
```dart
SiglipModelConfig(
  version: SiglipModelVersion.siglip1,
  vocabularySize: 32000,
  imageSize: 224,
  imageChannels: 3,
  maxTextLength: 64,
  embeddingDimension: 768,
  visionOutputTensorName: 'pooler_output',
  textOutputTensorName: 'pooler_output',
  hasProjectionLayer: false,
  imageMean: [0.5, 0.5, 0.5],
  imageStd: [0.5, 0.5, 0.5],
);
```

### SigLIP-2 Configuration
```dart
SiglipModelConfig(
  version: SiglipModelVersion.siglip2,
  vocabularySize: 256000,
  imageSize: 256,  // Larger input size
  imageChannels: 3,
  maxTextLength: 64,
  embeddingDimension: 768,
  visionOutputTensorName: 'pooler_output',  // Update after inspecting model
  textOutputTensorName: 'pooler_output',     // Update after inspecting model
  hasProjectionLayer: true,  // SigLIP-2 includes projection
  imageMean: [0.5, 0.5, 0.5],
  imageStd: [0.5, 0.5, 0.5],
);
```

## Expected Improvements with SigLIP-2

1. **Better Semantic Matching**: Improved understanding of text-image relationships
2. **Multilingual Support**: Enhanced handling of Taglish and Filipino queries
3. **Larger Vocabulary**: Better tokenization of diverse languages
4. **Projection Layers**: Proper alignment of vision and text embeddings

## Performance Considerations

- **SigLIP-2 is slower**: 256x256 images have 30% more pixels than 224x224
- **Larger models**: FP32 models are larger than quantized versions
- **Better accuracy**: Trade-off between speed and search quality

## Debugging

### Check Output Tensor Names

The actual output tensor names may differ from the defaults. To verify:

1. Run the app with SigLIP-2
2. Check debug logs for: `OnnxSiglipInference: Vision model output names: [...]`
3. Update configuration if tensor names differ

### Verify Embeddings

```dart
// Generate test embeddings
final textEmbedding = await embeddingService.generateEmbedding('test query');
final imageEmbedding = await embeddingService.generateImageEmbedding(imageBytes);

// Check embedding properties
print('Text embedding length: ${textEmbedding.length}');
print('Image embedding length: ${imageEmbedding.length}');

// Compute similarity
final similarity = _cosineSimilarity(textEmbedding, imageEmbedding);
print('Similarity: $similarity');
// Good matches should be > 0.3, poor matches < 0.1
```

## Troubleshooting

### Model Not Loading
- Verify asset files exist in `assets/models/`
- Check `pubspec.yaml` includes assets directory
- Run `flutter clean` and rebuild

### Wrong Output Tensor Names
- Check debug logs during initialization
- Update `visionOutputTensorName` and `textOutputTensorName` in config
- Common names: `pooler_output`, `image_embeds`, `text_embeds`, `last_hidden_state`

### Poor Search Results
- Verify `hasProjectionLayer` is correct for your model
- Check if model includes proper pooling/projection heads
- May need custom ONNX export with projection layers

## Next Steps

1. **Test Search Quality**: Compare SigLIP-1 vs SigLIP-2 search results
2. **Measure Performance**: Profile embedding generation time
3. **Optimize Models**: Consider quantizing SigLIP-2 to INT8 for speed
4. **Verify Tensor Names**: Update config after inspecting actual model outputs

---

*Last Updated: February 2, 2026*
