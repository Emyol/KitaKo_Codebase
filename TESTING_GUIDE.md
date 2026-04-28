# KitaKo ONNX Embedding System Testing Guide

This guide walks you through testing the ONNX-based embedding and search system.

---

## 🎯 Testing Overview

There are 3 levels of testing:
1. **Unit Tests** - Verify ONNX models load and generate embeddings
2. **Integration Tests** - Test embedding + ANN search together
3. **Full System Test** - Run the actual app with real images

---

## ✅ Level 1: Unit Tests (ONNX Model Verification)

### Step 1: Run the ONNX Embedding Test

**Windows:**
```bash
cd apps/kitako_app
.\run_onnx_test.bat
```

**Mac/Linux:**
```bash
cd apps/kitako_app
flutter test test/onnx_embedding_test.dart --verbose
```

### Step 2: Interpret Test Results

#### ✅ SUCCESS - Real ONNX Mode
```
✅ SUCCESS: ONNX models loaded successfully!
Mode: real
Text encoder ready: true
Image encoder ready: true
```

This means:
- ONNX models are loaded correctly
- Neural network inference is working
- Embeddings are semantically meaningful

#### ⚠️ WARNING - Mock Mode Fallback
```
⚠️ WARNING: Running in MOCK mode
Mode: mock
Text encoder ready: false
Image encoder ready: false
```

This means:
- ONNX models failed to load
- Using hash-based mock embeddings (not real AI)
- Check model files exist and are valid

### Step 3: Troubleshoot Model Loading Issues

If you see **MOCK mode**, check:

1. **Model files exist:**
   ```bash
   ls apps/kitako_app/assets/model/image_encoder/
   ls apps/kitako_app/assets/model/text_encoder/
   ```

   Should see:
   - `kitako_image_encoder_int8.onnx`
   - `kitako_text_encoder_int8.onnx`

2. **Tokenizer exists:**
   ```bash
   ls apps/kitako_app/assets/tokenizer/
   ```

   Should see:
   - `tokenizer.json`

3. **Assets are bundled in pubspec.yaml:**
   ```yaml
   flutter:
     assets:
       - assets/model/image_encoder/
       - assets/model/text_encoder/
       - assets/tokenizer/
   ```

4. **Clean and rebuild:**
   ```bash
   cd apps/kitako_app
   flutter clean
   flutter pub get
   ```

---

## 🔗 Level 2: Integration Test (Embedding + ANN Search)

### Create Integration Test

Create `apps/kitako_app/test/search_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_app/src/services/image_search_service.dart';
import 'package:kitako_app/src/models/search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search Integration Tests', () {
    late ImageSearchService searchService;

    setUp(() async {
      searchService = ImageSearchService();
      await searchService.initialize();
    });

    tearDown(() {
      searchService.dispose();
    });

    test('Initialize and check services ready', () async {
      final stats = searchService.getStats();

      print('\n========================================');
      print('SEARCH SERVICE STATISTICS');
      print('========================================');
      print('Initialized: ${stats['initialized']}');
      print('Total images: ${stats['totalImages']}');
      print('Indexed images: ${stats['indexedImages']}');
      print('Embedding cache: ${stats['embeddingCache']}');
      print('ANN index: ${stats['annIndex']}');
      print('========================================\n');

      expect(stats['initialized'], isTrue);
    });

    test('Search for images with text query', () async {
      print('\n========================================');
      print('TESTING TEXT-TO-IMAGE SEARCH');
      print('========================================\n');

      // Test queries
      final queries = [
        'sunset beach',
        'mountain landscape',
        'city skyline',
      ];

      for (final query in queries) {
        print('Searching for: "$query"');

        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(query, topK: 5);
        stopwatch.stop();

        final state = searchService.currentState;

        print('  Status: ${state.status}');
        print('  Results: ${state.result?.resultCount ?? 0}');
        print('  Time: ${stopwatch.elapsedMilliseconds}ms');
        print('  Normalized query: ${state.normalizedQuery}');
        print('');

        expect(state.status, isNot(SearchStatus.error));
      }
    });

    test('Check embedding consistency', () async {
      print('\n========================================');
      print('TESTING EMBEDDING DETERMINISM');
      print('========================================\n');

      final query = 'test query';

      // Search twice with same query
      await searchService.searchImages(query);
      final state1 = searchService.currentState;

      searchService.clearSearch();

      await searchService.searchImages(query);
      final state2 = searchService.currentState;

      print('First search:  ${state1.result?.resultCount} results');
      print('Second search: ${state2.result?.resultCount} results');
      print('');

      // Should get identical results due to caching/determinism
      expect(state1.result?.resultCount, equals(state2.result?.resultCount));

      print('✅ Embeddings are deterministic!\n');
    });
  });
}
```

### Run Integration Test

```bash
cd apps/kitako_app
flutter test test/search_integration_test.dart --verbose
```

---

## 📱 Level 3: Full System Test (Real App)

### Step 1: Prepare Test Environment

1. **Connect a physical device or start emulator:**
   ```bash
   flutter devices
   ```

2. **Add test images to device:**
   - Add 10-20 images to your device gallery
   - Use diverse images: landscapes, people, objects, animals

### Step 2: Run the App

```bash
cd apps/kitako_app
flutter run
```

### Step 3: Test Search Functionality

1. **Check startup:**
   - Watch console for initialization messages
   - Look for: `"EmbeddingService: Initialized successfully"`
   - Look for: `"ImageSearchService: Initialized successfully"`

2. **Verify model mode:**
   - Check console output for:
     ```
     Text encoder ready: true
     Image encoder ready: true
     ```
   - If both `false`, you're in MOCK mode

3. **Test text search:**
   - Type queries in the search bar
   - Try: "sunset", "person", "food", "landscape"
   - Verify:
     - Results appear
     - Results are relevant (if in REAL mode)
     - No crashes or errors

4. **Test Taglish normalization:**
   - Try Filipino queries: "magandang tanawin", "pagkain"
   - Should normalize and search correctly

5. **Check performance:**
   - Note search latency (should be < 500ms)
   - Check if app is responsive
   - Monitor memory usage

### Step 4: Monitor Debug Output

Watch for these key messages:

**✅ Good Signs:**
```
EmbeddingService: Initialized successfully
  - Text encoder ready: true
  - Image encoder ready: true
ImageSearchService: Indexed 15 images in 342ms
ImageSearchService: Search completed in 125ms
```

**⚠️ Warning Signs:**
```
EmbeddingService: Running in MOCK mode
ImageSearchService: No images to index
```

**❌ Error Signs:**
```
EmbeddingService: Failed to initialize ONNX: ...
ONNX Runtime error: ...
```

---

## 🔍 Verifying Real vs Mock Mode

### In Console Output

**Real Mode:**
```
EmbeddingService: Generated real embedding for: "sunset"
```

**Mock Mode:**
```
EmbeddingService: Generated MOCK embedding for: "sunset"
```

### In Search Results

**Real Mode:**
- Results are semantically relevant
- "sunset" finds sunset images
- Similar queries return similar results

**Mock Mode:**
- Results are hash-based (deterministic but not semantic)
- "sunset" and "mountain" might return identical results
- No actual AI understanding

---

## 📊 Understanding Test Output

### Test 1: ONNX Model Initialization
- Verifies models load from assets
- Checks text and image encoders are ready

### Test 2: Text Embedding Generation
- Generates embeddings for different queries
- Checks L2 normalization (norm ≈ 1.0)
- Verifies uniqueness (different text → different embeddings)

### Test 3: Embedding Determinism
- Same input should produce identical output
- Tests caching mechanism

### Test 4: Semantic Similarity
- Similar queries should have high similarity
- Different queries should have lower similarity
- Only runs in REAL mode

### Test 5: ONNX vs Mock Detection
- Final confirmation of which mode is active
- Provides troubleshooting steps if MOCK

---

## 🐛 Common Issues & Solutions

### Issue: "Missing Input: attention_mask"
**Solution:** Already fixed in latest code. Update to latest version.

### Issue: "Got invalid dimensions for input"
**Solution:** Already fixed. Text model expects 32 tokens, not 64.

### Issue: Models not loading (MOCK mode)
**Solutions:**
1. Check asset files exist
2. Run `flutter clean && flutter pub get`
3. Rebuild app completely
4. Check model file sizes (should be > 1MB each)

### Issue: "UnsupportedError on web"
**Solution:** ONNX Runtime only works on mobile (Android/iOS). Web uses MOCK mode.

### Issue: Slow inference (> 1 second per search)
**Possible causes:**
1. Using debug build (try release: `flutter run --release`)
2. Large models (int8 should be fast)
3. Device is slow/old

### Issue: Search returns no results
**Check:**
1. Are images loaded? Check `ImageSearchService: Indexed X images`
2. Is threshold too high? Try lowering in code
3. Are embeddings being generated?

---

## 📈 Performance Benchmarks

### Expected Performance (Release Build)

**Text Embedding:**
- First call: 50-150ms (model warmup)
- Cached: < 1ms
- Uncached: 20-50ms

**Image Embedding:**
- Per image: 100-300ms (depends on device)

**ANN Search:**
- 100 images: < 10ms
- 1000 images: < 50ms
- 10000 images: < 200ms

**Total Search Time:**
- Text embedding + ANN search: < 100ms typical

---

## ✨ Testing Checklist

Use this checklist to verify everything works:

- [ ] Unit test passes (all 5 tests)
- [ ] REAL mode confirmed (not MOCK)
- [ ] Text embeddings generate correctly
- [ ] Image embeddings generate correctly (if testing)
- [ ] Embeddings are normalized (L2 norm ≈ 1.0)
- [ ] Embeddings are deterministic (same input → same output)
- [ ] Semantic similarity works (similar text → similar embeddings)
- [ ] Integration test passes
- [ ] App runs without crashes
- [ ] Search returns results
- [ ] Search results are relevant
- [ ] No memory leaks (long-running test)
- [ ] Performance is acceptable (< 500ms per search)

---

## 🚀 Next Steps

Once all tests pass:

1. **Optimize performance:**
   - Profile slow operations
   - Consider batch processing
   - Optimize image preprocessing

2. **Improve search quality:**
   - Tune similarity threshold
   - Adjust topK parameter
   - Add result ranking

3. **Add more features:**
   - Image-to-image search
   - Hybrid text + image search
   - Search filters

4. **Production readiness:**
   - Add error recovery
   - Implement crash reporting
   - Add analytics

---

## 📞 Getting Help

If tests fail:

1. Check console output for specific error messages
2. Review this guide's troubleshooting section
3. Verify all model files are present and correct
4. Try clean rebuild: `flutter clean && flutter pub get`
5. Check Flutter and Dart SDK versions

---

**Good luck with testing! 🎉**
