import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_app/src/services/embedding_service.dart';
import 'package:kitako_app/src/services/image_loader_service.dart';
import 'package:kitako_app/src/services/ann_search_service.dart';

/// Integration test for image indexing pipeline
///
/// This test verifies the complete pipeline:
/// 1. Load images from device gallery
/// 2. Generate embeddings for each image
/// 3. Index embeddings in ANN search
/// 4. Verify search works
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Image Indexing Pipeline', () {
    late ImageLoaderService imageLoader;
    late EmbeddingService embeddingService;
    late ANNSearchService searchService;

    setUpAll(() async {
      // ignore: avoid_print
      print('\n========================================');
      // ignore: avoid_print
      print('Image Indexing Integration Test');
      // ignore: avoid_print
      print('========================================\n');

      imageLoader = ImageLoaderService();
      embeddingService = EmbeddingService();
      searchService = ANNSearchService();
    });

    test('Complete Image Indexing Pipeline', () async {
      // ignore: avoid_print
      print('\n>>> STEP 1: Initialize Services');
      // ignore: avoid_print
      print('--------------------------------------------------');

      // Initialize image loader
      final imageLoaderReady = await imageLoader.initialize();
      expect(imageLoaderReady, true, reason: 'Image loader should initialize');
      // ignore: avoid_print
      print('✓ Image loader initialized');

      // Initialize embedding service
      final embeddingReady = await embeddingService.initialize();
      expect(embeddingReady, true, reason: 'Embedding service should initialize');
      // ignore: avoid_print
      print('✓ Embedding service initialized');

      // Initialize ANN search service
      await searchService.initialize();
      // ignore: avoid_print
      print('✓ ANN search service initialized');
      // ignore: avoid_print
      print('  Using native HNSW: ${searchService.usingNativeHnsw}');

      // Check if services are ready
      final stats = embeddingService.getCacheStats();
      final isRealMode = stats['mode'] == 'real';
      // ignore: avoid_print
      print('\nEmbedding mode: ${stats['mode']}');
      // ignore: avoid_print
      print('Text encoder ready: ${embeddingService.isTextReady}');
      // ignore: avoid_print
      print('Image encoder ready: ${embeddingService.isImageReady}');

      if (!isRealMode) {
        // ignore: avoid_print
        print('\n⚠️  WARNING: Running in MOCK mode');
        // ignore: avoid_print
        print('   Embeddings will be hash-based, not real ONNX inference');
        // ignore: avoid_print
        print('   For real inference, ensure .onnx models are in assets/');
      } else {
        // ignore: avoid_print
        print('\n✅ ONNX MODELS LOADED - Using real neural network inference!');
      }

      // ignore: avoid_print
      print('\n>>> STEP 2: Load Images from Gallery');
      // ignore: avoid_print
      print('--------------------------------------------------');

      final images = await imageLoader.loadDeviceImages();
      expect(images, isNotEmpty, reason: 'Should load at least some images');

      // ignore: avoid_print
      print('Total images available: ${images.length}');

      // Test with first 5 images (or fewer if less available)
      final testCount = images.length < 5 ? images.length : 5;
      // ignore: avoid_print
      print('Testing with first $testCount images\n');

      // ignore: avoid_print
      print('\n>>> STEP 3: Generate Embeddings and Index Images');
      // ignore: avoid_print
      print('--------------------------------------------------');

      final indexedImages = <int>[];
      final times = <int>[];

      for (int i = 0; i < testCount; i++) {
        final image = images[i];
        // ignore: avoid_print
        print('\nImage ${i + 1}/$testCount: ${image.name}');
        // ignore: avoid_print
        print('  Path: ${image.path}');
        final sizeMB = (image.sizeBytes ?? 0) / (1024 * 1024);
        // ignore: avoid_print
        print('  Size: ${sizeMB.toStringAsFixed(2)} MB');
        // ignore: avoid_print
        print('  Resolution: ${image.width}x${image.height}');

        // Load image bytes via ImageLoaderService (handles Android scoped storage)
        final imageBytes = await imageLoader.getImageBytes(image);

        if (imageBytes == null) {
          // ignore: avoid_print
          print('  ⚠️  Could not load image bytes, skipping');
          continue;
        }

        // ignore: avoid_print
        print('  ✓ Loaded ${imageBytes.length} bytes');

        // Generate embedding
        final stopwatch = Stopwatch()..start();
        final embedding =
            await embeddingService.generateImageEmbedding(imageBytes);
        stopwatch.stop();

        times.add(stopwatch.elapsedMilliseconds);
        // ignore: avoid_print
        print('  ✓ Generated embedding in ${stopwatch.elapsedMilliseconds}ms');
        // ignore: avoid_print
        print('  ✓ Embedding dimension: ${embedding.length}');

        // Verify embedding quality
        expect(embedding.length, 768,
            reason: 'Embedding should be 768-dimensional');

        // Check L2 norm (should be close to 1.0 for normalized embeddings)
        double norm = 0.0;
        for (final value in embedding) {
          norm += value * value;
        }
        norm = _sqrt(norm);
        // ignore: avoid_print
        print('  ✓ L2 norm: ${norm.toStringAsFixed(6)} (should be ≈ 1.0)');

        expect(norm, closeTo(1.0, 0.1),
            reason: 'Embedding should be normalized');

        // Index the image immediately
        await searchService.indexImage(image, embedding);
        indexedImages.add(i);

        // ignore: avoid_print
        print('  ✓ Image indexed successfully');
      }

      final actualCount = indexedImages.length;
      expect(actualCount, greaterThan(0),
          reason: 'Should have processed at least one image');

      // ignore: avoid_print
      print('\n✓ Processed and indexed $actualCount images successfully');

      // Performance statistics
      if (times.isNotEmpty) {
        final avgTime = times.reduce((a, b) => a + b) / times.length;
        final minTime = times.reduce((a, b) => a < b ? a : b);
        final maxTime = times.reduce((a, b) => a > b ? a : b);

        // ignore: avoid_print
        print('\n>>> Performance Statistics:');
        // ignore: avoid_print
        print('Images processed: $actualCount');
        // ignore: avoid_print
        print('Average time: ${avgTime.toStringAsFixed(2)}ms per image');
        // ignore: avoid_print
        print('Min time: ${minTime}ms');
        // ignore: avoid_print
        print('Max time: ${maxTime}ms');
        // ignore: avoid_print
        print('Total time: ${times.reduce((a, b) => a + b)}ms');

        if (isRealMode) {
          if (avgTime < 100) {
            // ignore: avoid_print
            print('\n✅ EXCELLENT performance for mobile ONNX inference!');
          } else if (avgTime < 200) {
            // ignore: avoid_print
            print('\n✅ GOOD performance for mobile ONNX inference');
          } else if (avgTime < 500) {
            // ignore: avoid_print
            print('\n⚠️  ACCEPTABLE performance (consider optimization)');
          } else {
            // ignore: avoid_print
            print(
                '\n⚠️  SLOW performance (check device specs or use release build)');
          }
        }
      }

      // ignore: avoid_print
      print('\n>>> STEP 4: Verify Indexing with Search Test');
      // ignore: avoid_print
      print('--------------------------------------------------');

      // Test 1: Search using first image (should return similar images)
      // ignore: avoid_print
      print('\nTest 1: Similarity search');
      // ignore: avoid_print
      print(
          'Searching for images similar to: ${images[indexedImages[0]].name}');

      // Re-generate embedding for first image to use as query
      final firstImageBytes = await imageLoader.getImageBytes(images[indexedImages[0]]);
      expect(firstImageBytes, isNotNull, reason: 'Should get bytes for first image');
      final queryEmbedding =
          await embeddingService.generateImageEmbedding(firstImageBytes!);

      final searchResults = await searchService.searchSimilar(
        queryEmbedding,
        k: actualCount,
      );

      expect(searchResults, isNotEmpty, reason: 'Search should return results');
      // ignore: avoid_print
      print('✓ Found ${searchResults.length} similar images');

      // ignore: avoid_print
      print('\nTop ${searchResults.length} results:');
      for (int i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
        // ignore: avoid_print
        print('${i + 1}. ${result.name}');
      }

      // ignore: avoid_print
      print('\n✅ Similarity search PASSED!');

      // Test 2: Text-to-image search
      if (embeddingService.isTextReady) {
        // ignore: avoid_print
        print('\nTest 2: Text-to-image search');
        // ignore: avoid_print
        print('Searching with text query: "photo"...');

        final textEmbedding = await embeddingService.generateEmbedding('photo');
        final textSearchResults = await searchService.searchSimilar(
          textEmbedding,
          k: 3,
        );

        expect(textSearchResults, isNotEmpty,
            reason: 'Text search should return results');
        // ignore: avoid_print
        print('✓ Found ${textSearchResults.length} results');

        // ignore: avoid_print
        print('\nTop results for "photo":');
        for (int i = 0; i < textSearchResults.length; i++) {
          final result = textSearchResults[i];
          // ignore: avoid_print
          print('${i + 1}. ${result.name}');
        }

        // ignore: avoid_print
        print('\n✅ Text-to-image search PASSED!');
      } else {
        // ignore: avoid_print
        print('\n⚠️  Skipping text-to-image search (text encoder not ready)');
      }

      // ignore: avoid_print
      print('\n>>> STEP 5: Verify Index Persistence');
      // ignore: avoid_print
      print('--------------------------------------------------');

      // Get index statistics
      final indexSize = searchService.indexSize;
      // ignore: avoid_print
      print('Index size: $indexSize images');
      expect(indexSize, actualCount,
          reason: 'Index should contain all added images');

      final indexStats = searchService.getIndexStats();
      // ignore: avoid_print
      print('Index stats: $indexStats');

      // ignore: avoid_print
      print('✓ Index contains correct number of images');

      // ignore: avoid_print
      print('\n========================================');
      // ignore: avoid_print
      print('✅ ALL TESTS PASSED!');
      // ignore: avoid_print
      print('========================================\n');

      // ignore: avoid_print
      print('Summary:');
      // ignore: avoid_print
      print('- Loaded $actualCount images from gallery');
      // ignore: avoid_print
      print(
          '- Generated embeddings using ${isRealMode ? "ONNX" : "MOCK"} inference');
      // ignore: avoid_print
      print('- Indexed all embeddings in ANN search');
      // ignore: avoid_print
      print('- Verified search functionality works correctly');
      // ignore: avoid_print
      print('- Image indexing pipeline is working! 🎉');
    }, timeout: const Timeout(Duration(minutes: 10)));

    tearDownAll(() {
      embeddingService.dispose();
      imageLoader.dispose();
      searchService.dispose();
      // ignore: avoid_print
      print('\n✓ Services cleaned up');
    });
  });
}

/// Simple sqrt implementation for L2 norm calculation
double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
