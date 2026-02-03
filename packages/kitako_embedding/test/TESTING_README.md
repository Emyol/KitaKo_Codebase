# SigLIP Model Testing Guide

This directory contains comprehensive unit tests for validating SigLIP model implementations.

## Test Coverage

### 1. Model File Validation
- ✓ Checks if model files exist
- ✓ Validates file sizes (SigLIP-1: ~210MB, SigLIP-2: ~1.5GB)
- ✓ Confirms tokenizer availability

### 2. Model Initialization
- ✓ Loads SigLIP-1 quantized models
- ✓ Loads SigLIP-2 FP32 models
- ✓ Verifies configuration (image size, vocab)

### 3. Image Embedding Tests
- ✓ Generates 768-dimensional embeddings
- ✓ Validates L2 normalization (norm ≈ 1.0)
- ✓ Tests deterministic behavior
- ✓ Verifies different images → different embeddings

### 4. Text Embedding Tests
- ✓ Generates 768-dimensional embeddings
- ✓ Validates L2 normalization
- ✓ Tests deterministic behavior
- ✓ Similar texts → high similarity
- ✓ Unrelated texts → low similarity

### 5. SigLIP-1 vs SigLIP-2 Comparison
- ✓ **Critical Test**: Verifies projection layers
- ✓ SigLIP-1: Low cross-modal similarity (0.05-0.15)
- ✓ SigLIP-2: High cross-modal similarity (0.75-0.95)
- ✓ Measures improvement (should be 5-10x)

### 6. Performance Benchmarks
- ✓ Image embedding speed
- ✓ Text embedding speed
- ✓ Should complete within reasonable time

### 7. Edge Cases
- ✓ Empty text
- ✓ Very long text (truncation)
- ✓ Special characters
- ✓ Non-English text

## Running the Tests

### Quick Run
```powershell
cd packages\kitako_embedding
flutter test test/siglip_model_test.dart
```

### Detailed Output
```powershell
flutter test test/siglip_model_test.dart --reporter expanded
```

### Run All Tests with Script
```powershell
.\test\run_tests.ps1
```

## Expected Results

### Successful Test Output
```
✓ SigLIP-1 Vision: 99.2 MB
✓ SigLIP-1 Text: 111.4 MB
✓ SigLIP-2 Vision: 371.1 MB
✓ SigLIP-2 Text: 1102.8 MB
✓ Tokenizer: 2048.5 KB

Cross-modal similarity comparison:
  SigLIP-1 (no projection): 0.0839
  SigLIP-2 (with projection): 0.8745
  Improvement: 941.2%

✓ EXCELLENT: SigLIP-2 has strong cross-modal alignment
```

### What the Tests Verify

#### SigLIP-1 (Quantized, No Projection)
- ✓ Models load successfully
- ✓ Embeddings are 768D and normalized
- ✓ **Cross-modal similarity: 0.05 - 0.15** (LOW)
- ✓ This confirms missing projection layers
- ✗ Not suitable for production (weak alignment)

#### SigLIP-2 (FP32, With Projection)
- ✓ Models load successfully  
- ✓ Embeddings are 768D and normalized
- ✓ **Cross-modal similarity: 0.75 - 0.95** (HIGH)
- ✓ This confirms projection layers working
- ✓ Suitable for production (strong alignment)

## Interpreting Results

### Good Results ✓
```
SigLIP-1: similarity = 0.0839
SigLIP-2: similarity = 0.8745
Ratio: 10.4x improvement
```
**Interpretation**: Projection layers are working correctly!

### Bad Results ✗
```
SigLIP-1: similarity = 0.0839
SigLIP-2: similarity = 0.1245
Ratio: 1.5x improvement
```
**Interpretation**: SigLIP-2 may not have projection layers, or models are incorrect.

### Edge Case: Both Low
```
SigLIP-1: similarity = 0.0839
SigLIP-2: similarity = 0.0912
Ratio: 1.1x improvement
```
**Problem**: SigLIP-2 is not actually SigLIP-2, likely using wrong model files.

## Troubleshooting

### Test Fails: "Model file not found"
**Solution**: Update paths in `siglip_model_test.dart`:
```dart
const modelsBasePath = 'YOUR_PATH_HERE';
```

### Test Fails: "Models load but similarity is low"
**Causes**:
1. Wrong model files (both might be SigLIP-1)
2. Model corruption during download/transfer
3. ONNX Runtime version mismatch

**Solution**: Re-download models, verify checksums.

### Test Fails: "Out of memory"
**Cause**: SigLIP-2 models are large (1.5GB)

**Solution**: Run tests on machine with >4GB available RAM.

### Test Hangs: "Never completes"
**Cause**: ONNX Runtime initialization issue

**Solution**: 
1. Check ONNX Runtime installation
2. Verify model compatibility
3. Run in Release mode: `flutter test --release`

## Performance Expectations

### Desktop (Windows/Mac/Linux)
- Image embedding: 100-300ms
- Text embedding: 50-150ms

### Mobile (Android/iOS)
- Image embedding: 300-800ms
- Text embedding: 150-400ms

### CI/CD Environment
- May be slower, set timeout: `--timeout 60s`

## Continuous Integration

Add to your CI pipeline:
```yaml
- name: Run Model Tests
  run: |
    cd packages/kitako_embedding
    flutter test test/siglip_model_test.dart --timeout 60s
```

## Test Data

Tests use:
- **Synthetic images**: Generated via `ImagePreprocessor.createTestImage()`
- **Fixed text queries**: "cat on a table", etc.
- **Random images**: For difference tests

For production validation, add real image tests:
```dart
test('Real cat image has high similarity to "cat" query', () async {
  final catImage = await loadRealImage('test_assets/cat.jpg');
  final imgEmbed = await siglip.embedImage(catImage);
  final textEmbed = await siglip.embedText('cat');
  
  final similarity = cosineSimilarity(imgEmbed, textEmbed);
  expect(similarity, greaterThan(0.7));
});
```

## Next Steps

After all tests pass:

1. **Deploy to device**: Run `setup_siglip2.ps1`
2. **Integration test**: Test in actual app
3. **User acceptance**: Verify search quality with real queries
4. **Performance monitoring**: Track latency in production

## Questions?

- See [SIGLIP_ANALYSIS.md](../../apps/kitako_app/SIGLIP_ANALYSIS.md) for technical details
- See [SIGLIP_QUICKSTART.md](../../apps/kitako_app/SIGLIP_QUICKSTART.md) for deployment guide
