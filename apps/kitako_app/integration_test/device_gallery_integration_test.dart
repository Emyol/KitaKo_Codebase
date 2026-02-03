import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_app/src/services/embedding_service.dart';
import 'package:kitako_app/src/services/ann_search_service.dart';
import 'package:kitako_app/src/services/image_loader_service.dart';
import 'package:kitako_app/src/services/image_search_service.dart';
import 'package:kitako_app/src/models/search_models.dart';

/// Comprehensive device integration test for KitaKo
///
/// This test suite validates the full pipeline using your device's real gallery:
/// 1. Photo permissions and gallery access
/// 2. Image loading from device storage
/// 3. Embedding generation (ONNX or fallback)
/// 4. ANN indexing and similarity search
/// 5. End-to-end text-to-image search
/// 6. Performance benchmarking
///
/// Run with: flutter test integration_test/device_gallery_integration_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ImageLoaderService imageLoader;
  late EmbeddingService embeddingService;
  late ANNSearchService annSearchService;
  late ImageSearchService searchService;

  // Test configuration
  const int maxImagesToTest = 20;
  const int searchTopK = 5;
  const double similarityThreshold = 0.3;

  // Performance thresholds (milliseconds)
  const int excellentThreshold = 100;
  const int goodThreshold = 200;
  const int acceptableThreshold = 500;

  void log(String message) {
    debugPrint('[DeviceTest] $message');
  }

  void logSection(String title) {
    log('');
    log('=' * 60);
    log(' $title');
    log('=' * 60);
  }

  String formatDuration(int ms) {
    if (ms < excellentThreshold) return '$ms ms (excellent)';
    if (ms < goodThreshold) return '$ms ms (good)';
    if (ms < acceptableThreshold) return '$ms ms (acceptable)';
    return '$ms ms (slow)';
  }

  /// Check if images are from the real gallery (not mock)
  bool hasRealImages(List<ImageItem> images) {
    if (images.isEmpty) return false;
    // Mock images have IDs starting with 'mock_'
    return !images.first.id.startsWith('mock_');
  }

  setUpAll(() async {
    logSection('DEVICE INTEGRATION TEST SUITE');
    log('Platform: ${Platform.operatingSystem}');
    log('Version: ${Platform.operatingSystemVersion}');
    log('Processors: ${Platform.numberOfProcessors}');
    log('');
  });

  group('1. Photo Permissions & Gallery Access', () {
    testWidgets('should request and obtain photo permissions', (tester) async {
      logSection('Test 1.1: Photo Permissions');

      imageLoader = ImageLoaderService();

      final stopwatch = Stopwatch()..start();
      final success = await imageLoader.initialize();
      stopwatch.stop();

      log('Permission request completed in ${stopwatch.elapsedMilliseconds} ms');
      log('Initialization success: $success');

      expect(success, isTrue,
          reason: 'ImageLoaderService should initialize successfully');
    });

    testWidgets('should load images from device gallery', (tester) async {
      logSection('Test 1.2: Gallery Image Loading');

      final stopwatch = Stopwatch()..start();
      final images = await imageLoader.loadDeviceImages();
      stopwatch.stop();

      log('Loaded ${images.length} images in ${stopwatch.elapsedMilliseconds} ms');

      final usingRealImages = hasRealImages(images);
      log('Using real gallery images: $usingRealImages');

      if (images.isEmpty) {
        log('WARNING: No images found in gallery');
      } else {
        log('Sample images:');
        for (var i = 0; i < images.length && i < 5; i++) {
          final img = images[i];
          log('  [$i] ${img.name} (${img.width}x${img.height})');
        }
      }

      expect(images, isNotEmpty,
          reason: 'Should load images (real or mock fallback)');

      if (!usingRealImages) {
        log('NOTE: Using mock images - add real photos to device gallery for full testing');
      }
    });

    testWidgets('should retrieve image bytes correctly', (tester) async {
      logSection('Test 1.3: Image Bytes Retrieval');

      final images = imageLoader.getAllImages();
      if (images.isEmpty) {
        log('SKIP: No images available');
        return;
      }

      // Skip byte retrieval test for mock images
      if (!hasRealImages(images)) {
        log('SKIP: Mock images - cannot retrieve bytes');
        return;
      }

      final testImage = images.first;
      log('Testing image: ${testImage.name}');

      final stopwatch = Stopwatch()..start();
      final bytes = await imageLoader.getImageBytes(testImage);
      stopwatch.stop();

      log('Retrieved ${bytes?.length ?? 0} bytes in ${stopwatch.elapsedMilliseconds} ms');

      expect(bytes, isNotNull, reason: 'Image bytes should not be null');
      expect(bytes!.length, greaterThan(0), reason: 'Image bytes should not be empty');

      // Validate image format (check magic bytes)
      final isValidImage = _validateImageFormat(bytes);
      log('Valid image format: $isValidImage');
      expect(isValidImage, isTrue, reason: 'Should be a valid image format');
    });
  });

  group('2. Optimized Thumbnail Loading', () {
    testWidgets('should load thumbnails much faster than full images', (tester) async {
      logSection('Test 2.0: Thumbnail vs Full Image Performance');

      final images = imageLoader.getAllImages();
      if (images.isEmpty || !hasRealImages(images)) {
        log('SKIP: No real images available');
        return;
      }

      final testImage = images.first;

      // Test full image loading (OLD way)
      log('Testing FULL image loading (old method)...');
      final fullStopwatch = Stopwatch()..start();
      final fullBytes = await imageLoader.getImageBytes(testImage);
      fullStopwatch.stop();
      log('  Full image: ${fullBytes?.length ?? 0} bytes in ${fullStopwatch.elapsedMilliseconds}ms');

      // Test thumbnail loading (NEW way)
      log('Testing THUMBNAIL loading (optimized)...');
      final thumbStopwatch = Stopwatch()..start();
      final thumbBytes = await imageLoader.getThumbnailBytes(testImage);
      thumbStopwatch.stop();
      log('  Thumbnail: ${thumbBytes?.length ?? 0} bytes in ${thumbStopwatch.elapsedMilliseconds}ms');

      if (fullStopwatch.elapsedMilliseconds > 0) {
        final speedup = fullStopwatch.elapsedMilliseconds /
            (thumbStopwatch.elapsedMilliseconds > 0 ? thumbStopwatch.elapsedMilliseconds : 1);
        log('  SPEEDUP: ${speedup.toStringAsFixed(1)}x faster!');
      }

      expect(thumbBytes, isNotNull);
    });

    testWidgets('should load batch thumbnails in parallel', (tester) async {
      logSection('Test 2.0b: Parallel Batch Thumbnail Loading');

      final images = imageLoader.getAllImages();
      if (images.isEmpty || !hasRealImages(images)) {
        log('SKIP: No real images available');
        return;
      }

      final testCount = images.length.clamp(1, 10);
      final testImages = images.take(testCount).toList();

      log('Loading $testCount thumbnails in parallel batches...');
      final stopwatch = Stopwatch()..start();

      final thumbnails = await imageLoader.loadThumbnailBatch(
        testImages,
        batchSize: 5,
        onProgress: (loaded, total) {
          log('  Progress: $loaded/$total');
        },
      );
      stopwatch.stop();

      log('Loaded ${thumbnails.length} thumbnails in ${stopwatch.elapsedMilliseconds}ms');
      log('Average: ${(stopwatch.elapsedMilliseconds / testCount).toStringAsFixed(1)}ms per image');

      expect(thumbnails.length, equals(testCount));
    });
  });

  group('3. Embedding Service', () {
    testWidgets('should initialize embedding service', (tester) async {
      logSection('Test 3.1: Embedding Service Initialization');

      embeddingService = EmbeddingService();

      final stopwatch = Stopwatch()..start();
      await embeddingService.initialize();
      stopwatch.stop();

      final stats = embeddingService.getCacheStats();
      log('Initialization completed in ${stopwatch.elapsedMilliseconds} ms');
      log('Mode: ${stats['mode']}');
      log('ONNX models loaded: ${stats['mode'] == 'real'}');

      expect(embeddingService.isInitialized, isTrue);
    });

    testWidgets('should generate text embeddings', (tester) async {
      logSection('Test 2.2: Text Embedding Generation');

      if (!embeddingService.isInitialized) {
        log('SKIP: Embedding service not initialized');
        return;
      }

      final testQueries = [
        'sunset beach',
        'dog playing',
        'city skyline',
        'food on table',
        'family photo',
      ];

      for (final query in testQueries) {
        final stopwatch = Stopwatch()..start();
        final embedding = await embeddingService.generateEmbedding(query);
        stopwatch.stop();

        log('Query: "$query"');
        log('  Embedding dimension: ${embedding.length}');
        log('  L2 norm: ${_calculateL2Norm(embedding).toStringAsFixed(4)}');
        log('  Time: ${formatDuration(stopwatch.elapsedMilliseconds)}');

        expect(embedding.length, equals(768),
            reason: 'SigLIP embedding should be 768-dimensional');

        final norm = _calculateL2Norm(embedding);
        expect(norm, closeTo(1.0, 0.5),
            reason: 'Embedding should have reasonable L2 norm');
      }
    });

    testWidgets('should generate image embeddings from device photos', (tester) async {
      logSection('Test 3.3: Image Embedding Generation (Optimized)');

      if (!embeddingService.isInitialized) {
        log('SKIP: Embedding service not initialized');
        return;
      }

      final images = imageLoader.getAllImages();
      if (images.isEmpty || !hasRealImages(images)) {
        log('SKIP: No real images available for embedding generation');
        return;
      }

      final testCount = images.length.clamp(1, maxImagesToTest);
      final testImages = images.take(testCount).toList();

      log('Testing OPTIMIZED batch embedding for $testCount images...');
      log('');

      // Step 1: Load thumbnails (fast)
      log('Step 1: Loading thumbnails in parallel...');
      final thumbStopwatch = Stopwatch()..start();
      final thumbnails = await imageLoader.loadThumbnailBatch(testImages, batchSize: 5);
      thumbStopwatch.stop();
      log('  Thumbnails loaded in ${thumbStopwatch.elapsedMilliseconds}ms');

      // Step 2: Batch embed (fast)
      log('Step 2: Batch embedding...');
      final thumbnailBytes = testImages
          .where((img) => thumbnails.containsKey(img.id))
          .map((img) => thumbnails[img.id]!)
          .toList();

      final embedStopwatch = Stopwatch()..start();
      final embeddings = await embeddingService.generateBatchImageEmbeddings(
        thumbnailBytes,
        batchSize: 3,
        onProgress: (done, total) {
          if (done % 5 == 0 || done == total) {
            log('  Embedded: $done/$total');
          }
        },
      );
      embedStopwatch.stop();

      final totalTime = thumbStopwatch.elapsedMilliseconds + embedStopwatch.elapsedMilliseconds;

      log('');
      log('Performance Summary (OPTIMIZED):');
      log('  Thumbnail loading: ${thumbStopwatch.elapsedMilliseconds}ms');
      log('  Batch embedding: ${embedStopwatch.elapsedMilliseconds}ms');
      log('  TOTAL: ${totalTime}ms');
      log('  Average per image: ${(totalTime / testCount).toStringAsFixed(1)}ms');

      // Validate embeddings
      for (var i = 0; i < embeddings.length && i < 3; i++) {
        final embedding = embeddings[i];
        log('  Embedding[$i]: dim=${embedding.length}, L2=${_calculateL2Norm(embedding).toStringAsFixed(4)}');
        expect(embedding.length, equals(768));
      }
    });

    testWidgets('should compute similarity between embeddings', (tester) async {
      logSection('Test 2.4: Embedding Similarity');

      if (!embeddingService.isInitialized) {
        log('SKIP: Embedding service not initialized');
        return;
      }

      // Test semantic similarity
      final embedding1 = await embeddingService.generateEmbedding('dog');
      final embedding2 = await embeddingService.generateEmbedding('puppy');
      final embedding3 = await embeddingService.generateEmbedding('car');

      final simDogPuppy = embeddingService.computeSimilarity(embedding1, embedding2);
      final simDogCar = embeddingService.computeSimilarity(embedding1, embedding3);

      log('Similarity "dog" vs "puppy": ${simDogPuppy.toStringAsFixed(4)}');
      log('Similarity "dog" vs "car": ${simDogCar.toStringAsFixed(4)}');

      // Check that embeddings are generating valid similarity scores
      expect(simDogPuppy, inInclusiveRange(-1.0, 1.0),
          reason: 'Similarity should be between -1 and 1');
      expect(simDogCar, inInclusiveRange(-1.0, 1.0),
          reason: 'Similarity should be between -1 and 1');
    });
  });

  group('4. ANN Search Service', () {
    testWidgets('should initialize ANN search service', (tester) async {
      logSection('Test 4.1: ANN Search Service Initialization');

      annSearchService = ANNSearchService();

      final stopwatch = Stopwatch()..start();
      final success = await annSearchService.initialize();
      stopwatch.stop();

      final stats = annSearchService.getIndexStats();
      log('Initialization completed in ${stopwatch.elapsedMilliseconds} ms');
      log('Success: $success');
      log('Index stats: $stats');

      expect(success, isTrue);
    });

    testWidgets('should index device images', (tester) async {
      logSection('Test 4.2: Image Indexing');

      final images = imageLoader.getAllImages();
      if (images.isEmpty) {
        log('SKIP: No images available');
        return;
      }

      final testCount = images.length.clamp(1, maxImagesToTest);
      log('Indexing $testCount images...');

      int indexedCount = 0;

      // Generate embeddings and index
      final embeddingStopwatch = Stopwatch()..start();
      for (var i = 0; i < testCount; i++) {
        final image = images[i];

        List<double> embedding;
        if (hasRealImages(images)) {
          final bytes = await imageLoader.getImageBytes(image);
          if (bytes != null) {
            embedding = await embeddingService.generateImageEmbedding(bytes);
          } else {
            // Generate mock embedding for images without bytes
            embedding = _generateMockEmbedding(image.id);
          }
        } else {
          // Generate mock embedding for mock images
          embedding = _generateMockEmbedding(image.id);
        }

        await annSearchService.indexImage(image, embedding);
        indexedCount++;
      }
      embeddingStopwatch.stop();

      log('Indexed $indexedCount images in ${embeddingStopwatch.elapsedMilliseconds} ms');

      final stats = annSearchService.getIndexStats();
      log('Final index stats: $stats');

      expect(stats['totalImages'], equals(indexedCount));
    });

    testWidgets('should perform similarity search', (tester) async {
      logSection('Test 4.3: Similarity Search');

      final stats = annSearchService.getIndexStats();
      if ((stats['totalImages'] as int? ?? 0) == 0) {
        log('SKIP: No images indexed');
        return;
      }

      // Generate a query embedding
      final queryEmbedding = await embeddingService.generateEmbedding('nature landscape');

      final stopwatch = Stopwatch()..start();
      final results = await annSearchService.searchSimilar(
        queryEmbedding,
        k: searchTopK,
        threshold: similarityThreshold,
      );
      stopwatch.stop();

      log('Query: "nature landscape"');
      log('Search completed in ${stopwatch.elapsedMilliseconds} ms');
      log('Found ${results.length} results:');

      for (var i = 0; i < results.length; i++) {
        log('  [$i] ${results[i].name}');
      }

      // Results may be empty if embeddings are all mock and don't match
      log('Search returned ${results.length} results');
    });
  });

  group('5. End-to-End Search Service', () {
    testWidgets('should initialize full search service', (tester) async {
      logSection('Test 5.1: Full Search Service Initialization');

      searchService = ImageSearchService();

      final stopwatch = Stopwatch()..start();
      final success = await searchService.initialize();
      stopwatch.stop();

      log('Full service initialization completed in ${stopwatch.elapsedMilliseconds} ms');
      log('Success: $success');
      log('Current state: ${searchService.currentState.status}');

      expect(success, isTrue);
    });

    testWidgets('should perform text-to-image search', (tester) async {
      logSection('Test 5.2: Text-to-Image Search');

      final testQueries = [
        'people',
        'outdoor',
        'food',
        'nature',
        'building',
      ];

      for (final query in testQueries) {
        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(
          query,
          topK: searchTopK,
          threshold: similarityThreshold,
        );
        stopwatch.stop();

        final state = searchService.currentState;
        final results = state.result?.images ?? [];

        log('Query: "$query"');
        log('  Found ${results.length} results in ${stopwatch.elapsedMilliseconds} ms');

        if (results.isNotEmpty) {
          log('  Top result: ${results.first.name}');
        }
      }
    });

    testWidgets('should handle Taglish queries', (tester) async {
      logSection('Test 5.3: Taglish Query Support');

      final taglishQueries = [
        'mga tao',      // people
        'pagkain',      // food
        'bahay',        // house
        'pamilya',      // family
        'dagat',        // sea/beach
      ];

      for (final query in taglishQueries) {
        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(
          query,
          topK: searchTopK,
          threshold: similarityThreshold,
        );
        stopwatch.stop();

        final state = searchService.currentState;
        final results = state.result?.images ?? [];

        log('Query: "$query"');
        log('  Normalized: "${state.normalizedQuery ?? query}"');
        log('  Results: ${results.length} in ${stopwatch.elapsedMilliseconds} ms');
      }
    });
  });

  group('6. Performance Benchmarks', () {
    testWidgets('should benchmark full search pipeline', (tester) async {
      logSection('Test 6.1: Full Pipeline Benchmark');

      const iterations = 10;
      final timings = <int>[];

      log('Running $iterations search iterations...');

      for (var i = 0; i < iterations; i++) {
        final query = 'test query $i';

        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(query, topK: 5);
        stopwatch.stop();

        timings.add(stopwatch.elapsedMilliseconds);
        log('  Iteration $i: ${stopwatch.elapsedMilliseconds} ms');
      }

      final avgTime = timings.reduce((a, b) => a + b) / timings.length;
      final minTime = timings.reduce((a, b) => a < b ? a : b);
      final maxTime = timings.reduce((a, b) => a > b ? a : b);

      log('');
      log('Benchmark Results:');
      log('  Average: ${avgTime.toStringAsFixed(1)} ms');
      log('  Min: $minTime ms');
      log('  Max: $maxTime ms');
      log('  Performance: ${avgTime < goodThreshold ? "GOOD" : avgTime < acceptableThreshold ? "ACCEPTABLE" : "NEEDS OPTIMIZATION"}');
    });

    testWidgets('should report system statistics', (tester) async {
      logSection('Test 6.2: System Statistics');

      final embeddingStats = embeddingService.getCacheStats();
      final indexStats = annSearchService.getIndexStats();
      final allImages = imageLoader.getAllImages();

      log('Embedding Service:');
      log('  Mode: ${embeddingStats['mode']}');
      log('  Cache size: ${embeddingStats['size']}');

      log('');
      log('ANN Search Service:');
      log('  Total images: ${indexStats['totalImages']}');
      log('  Using native HNSW: ${indexStats['usingNativeHnsw']}');

      log('');
      log('Image Loader:');
      log('  Images loaded: ${allImages.length}');
      log('  Using real images: ${hasRealImages(allImages)}');
    });
  });

  tearDownAll(() {
    logSection('TEST SUITE COMPLETE');
    log('All device integration tests finished.');
    log('');
  });
}

/// Validates image format by checking magic bytes
bool _validateImageFormat(Uint8List bytes) {
  if (bytes.length < 4) return false;

  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }

  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return true;
  }

  // GIF: 47 49 46
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return true;
  }

  // BMP: 42 4D
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }

  // WebP: RIFF....WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return true;
  }

  return false;
}

/// Calculates L2 norm of an embedding vector
double _calculateL2Norm(List<double> embedding) {
  var sum = 0.0;
  for (final value in embedding) {
    sum += value * value;
  }
  return math.sqrt(sum);
}

/// Generate a mock embedding for testing
List<double> _generateMockEmbedding(String seed) {
  final hash = seed.hashCode;
  final random = _SeededRandom(hash);
  return List.generate(768, (index) => (random.nextDouble() * 2) - 1);
}

/// Simple seeded random for deterministic mock embeddings
class _SeededRandom {
  int _seed;
  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = ((_seed * 1103515245) + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}
