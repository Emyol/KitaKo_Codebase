import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_app/src/services/embedding_service.dart';
import 'package:kitako_app/src/services/image_loader_service.dart';
import 'package:kitako_app/src/services/image_search_service.dart';

/// REAL DEVICE INTEGRATION TEST
/// This test runs on a physical device/emulator and tests:
/// 1. Loading real images from device gallery
/// 2. Generating real ONNX embeddings for those images
/// 3. Performing similarity search
/// 4. Testing full end-to-end pipeline
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Real Device Image Embedding Tests', () {
    late EmbeddingService embeddingService;
    late ImageLoaderService imageLoader;
    late ImageSearchService searchService;

    setUpAll(() async {
      print('\n' + '=' * 60);
      print('KITAKO IMAGE EMBEDDING - REAL DEVICE TEST');
      print('=' * 60);
      print('This test will:');
      print('  1. Load images from your device gallery');
      print('  2. Generate ONNX embeddings for real images');
      print('  3. Test image similarity search');
      print('  4. Benchmark performance on device');
      print('=' * 60 + '\n');
    });

    setUp(() async {
      embeddingService = EmbeddingService();
      imageLoader = ImageLoaderService();
      searchService = ImageSearchService(
        embeddingService: embeddingService,
        imageLoader: imageLoader,
      );

      print('\n>>> Initializing services...');

      final embeddingInit = await embeddingService.initialize();
      final imageLoaderInit = await imageLoader.initialize();
      final searchInit = await searchService.initialize();

      print('✓ Embedding service: $embeddingInit');
      print('✓ Image loader: $imageLoaderInit');
      print('✓ Search service: $searchInit');

      final stats = embeddingService.getCacheStats();
      final mode = stats['mode'];

      print('\n>>> Service Status:');
      print('Mode: $mode');
      print('Text encoder ready: ${embeddingService.isTextReady}');
      print('Image encoder ready: ${embeddingService.isImageReady}');

      if (mode == 'real') {
        print('\n✅ ONNX MODELS LOADED - Using real neural network inference!');
      } else {
        print('\n⚠️  MOCK MODE - ONNX models not loaded, using fallback');
      }

      expect(embeddingInit, isTrue);
      expect(imageLoaderInit, isTrue);
      expect(searchInit, isTrue);
    });

    tearDown(() {
      embeddingService.dispose();
      imageLoader.dispose();
      searchService.dispose();
    });

    testWidgets('Load images from device gallery', (WidgetTester tester) async {
      print('\n' + '-' * 60);
      print('TEST 1: Loading Images from Device Gallery');
      print('-' * 60);

      final images = await imageLoader.loadDeviceImages();

      print('Total images found: ${images.length}');

      if (images.isEmpty) {
        print('\n⚠️  WARNING: No images found on device!');
        print('Please add some images to your device gallery and run again.');
        return;
      }

      print('\n>>> Sample Images (first 10):');
      final displayCount = images.length < 10 ? images.length : 10;
      for (int i = 0; i < displayCount; i++) {
        final img = images[i];
        print('${i + 1}. ${img.name}');
        print('   Path: ${img.path}');
        if (img.sizeBytes != null) {
          print('   Size: ${(img.sizeBytes! / 1024).toStringAsFixed(1)} KB');
        }
        if (img.width != null && img.height != null) {
          print('   Resolution: ${img.width}x${img.height}');
        }
      }

      expect(images, isNotEmpty);
      print('\n✅ Image loading successful!');
    });

    testWidgets('Generate embeddings for real device images', (WidgetTester tester) async {
      print('\n' + '-' * 60);
      print('TEST 2: Generating Real Image Embeddings');
      print('-' * 60);

      final images = await imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        print('⚠️  No images to process. Skipping test.');
        return;
      }

      final stats = embeddingService.getCacheStats();
      final isRealMode = stats['mode'] == 'real';

      if (!isRealMode) {
        print('⚠️  Running in MOCK mode - embeddings will be hash-based');
        print('   For real ONNX inference, ensure .onnx models are in assets/');
      }

      // Test with first 10 images (or fewer if less available)
      final testCount = images.length < 10 ? images.length : 10;
      final embeddings = <List<double>>[];
      final times = <int>[];

      print('\n>>> Processing $testCount images...\n');

      for (int i = 0; i < testCount; i++) {
        final image = images[i];
        print('Image ${i + 1}: ${image.name}');

        try {
          // Load actual image file bytes
          final imageFile = File(image.path);
          final imageBytes = await imageFile.readAsBytes();

          print('  ✓ Loaded ${imageBytes.length} bytes from file');

          final stopwatch = Stopwatch()..start();
          final embedding = await embeddingService.generateImageEmbedding(imageBytes);
          stopwatch.stop();

          embeddings.add(embedding);
          times.add(stopwatch.elapsedMilliseconds);

          print('  ✓ Generated embedding in ${stopwatch.elapsedMilliseconds}ms');
          print('  ✓ Embedding dimension: ${embedding.length}');
          print('  ✓ First 5 values: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).toList()}');

          // Calculate L2 norm
          final norm = _calculateL2Norm(embedding);
          print('  ✓ L2 norm: ${norm.toStringAsFixed(6)}');

          // Verify embedding is valid
          expect(embedding.length, EmbeddingService.embeddingDimension);

          if (isRealMode && embeddingService.isImageReady) {
            // In real mode with image encoder, embeddings should be normalized
            expect(norm, closeTo(1.0, 0.15),
              reason: 'Embeddings should be L2 normalized');
          }

          print('');
        } catch (e, stack) {
          print('  ❌ Error processing image: $e');
          print('  Stack: $stack');
          rethrow;
        }
      }

      // Performance statistics
      if (times.isNotEmpty) {
        final avgTime = times.reduce((a, b) => a + b) / times.length;
        final minTime = times.reduce((a, b) => a < b ? a : b);
        final maxTime = times.reduce((a, b) => a > b ? a : b);

        print('>>> Performance Statistics:');
        print('Images processed: $testCount');
        print('Average time: ${avgTime.toStringAsFixed(2)}ms per image');
        print('Min time: ${minTime}ms');
        print('Max time: ${maxTime}ms');
        print('Total time: ${times.reduce((a, b) => a + b)}ms');

        if (isRealMode && embeddingService.isImageReady) {
          print('\nExpected ONNX performance on mobile:');
          print('  - First inference: 100-500ms (model warmup)');
          print('  - Subsequent: 50-200ms per image');
        }
        print('');
      }

      // Test embedding uniqueness
      if (embeddings.length >= 2) {
        print('>>> Embedding Uniqueness Test:');
        print('Different images should produce different embeddings\n');

        bool allUnique = true;
        for (int i = 0; i < embeddings.length - 1; i++) {
          for (int j = i + 1; j < embeddings.length; j++) {
            final sim = _cosineSimilarity(embeddings[i], embeddings[j]);
            print('Similarity [Image $i ↔ Image $j]: ${sim.toStringAsFixed(4)}');

            // Embeddings should not be identical (similarity < 0.99)
            if (sim > 0.99) {
              allUnique = false;
            }
          }
        }

        if (allUnique && isRealMode) {
          print('\n✅ All embeddings are unique - ONNX inference is working!');
        } else if (!isRealMode) {
          print('\n⚠️  Mock mode - uniqueness not guaranteed');
        } else {
          print('\n⚠️  Some embeddings are too similar - check model');
        }
        print('');
      }

      print('✅ Image embedding generation complete!');
    });

    testWidgets('Test text-to-image search on device', (WidgetTester tester) async {
      print('\n' + '-' * 60);
      print('TEST 3: Text-to-Image Search');
      print('-' * 60);

      final images = await imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        print('⚠️  No images for search test. Skipping.');
        return;
      }

      final stats = searchService.getStats();
      print('Total images indexed: ${stats['indexedImages']}');
      print('Embedding mode: ${stats['embeddingCache']?['mode']}');

      // Test queries
      final queries = [
        'sunset beach',
        'person smiling',
        'food and drinks',
        'nature landscape',
        'city buildings',
      ];

      print('\n>>> Testing search queries:\n');

      for (final query in queries) {
        print('Query: "$query"');

        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(query, topK: 5);
        stopwatch.stop();

        final state = searchService.currentState;

        print('  Status: ${state.status}');
        print('  Results: ${state.result?.resultCount ?? 0} images');
        print('  Search time: ${stopwatch.elapsedMilliseconds}ms');
        print('  Normalized: "${state.normalizedQuery}"');

        if (state.result != null && state.result!.hasResults) {
          print('  Top results:');
          for (int i = 0; i < state.result!.images.length && i < 3; i++) {
            print('    ${i + 1}. ${state.result!.images[i].name}');
          }
        }

        expect(state.status, isNot(equals('error')));
        print('');
      }

      print('✅ Text-to-image search complete!');
    });

    testWidgets('Performance benchmark on real device', (WidgetTester tester) async {
      print('\n' + '-' * 60);
      print('TEST 4: Device Performance Benchmark');
      print('-' * 60);

      final images = await imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        print('⚠️  No images for benchmark. Skipping.');
        return;
      }

      // Get device info
      print('Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      print('Processors: ${Platform.numberOfProcessors}');
      print('');

      final stats = embeddingService.getCacheStats();
      final isRealMode = stats['mode'] == 'real';

      if (!isRealMode) {
        print('⚠️  Running in MOCK mode - benchmark not meaningful');
        return;
      }

      // Load first image for benchmarking
      final testImage = images.first;
      final imageFile = File(testImage.path);
      final imageBytes = await imageFile.readAsBytes();

      print('Benchmark image: ${testImage.name}');
      print('Image size: ${imageBytes.length} bytes\n');

      // Warm up
      print('>>> Warming up model...');
      await embeddingService.generateImageEmbedding(imageBytes);
      print('✓ Warmup complete\n');

      // Run benchmark
      final iterations = 10;
      final times = <int>[];

      print('>>> Running $iterations iterations...\n');

      for (int i = 0; i < iterations; i++) {
        final stopwatch = Stopwatch()..start();
        await embeddingService.generateImageEmbedding(imageBytes);
        stopwatch.stop();

        times.add(stopwatch.elapsedMilliseconds);
        print('Iteration ${i + 1}: ${stopwatch.elapsedMilliseconds}ms');
      }

      // Calculate statistics
      final avgTime = times.reduce((a, b) => a + b) / times.length;
      final minTime = times.reduce((a, b) => a < b ? a : b);
      final maxTime = times.reduce((a, b) => a > b ? a : b);

      times.sort();
      final medianTime = times[times.length ~/ 2];

      final variance = times.map((t) => (t - avgTime) * (t - avgTime))
          .reduce((a, b) => a + b) / times.length;
      final stdDev = _sqrt(variance);

      print('\n>>> Benchmark Results:');
      print('Average: ${avgTime.toStringAsFixed(2)}ms');
      print('Median: ${medianTime}ms');
      print('Min: ${minTime}ms');
      print('Max: ${maxTime}ms');
      print('Std Dev: ${stdDev.toStringAsFixed(2)}ms');
      print('');

      // Throughput calculation
      final avgThroughput = 1000 / avgTime;
      print('Throughput: ${avgThroughput.toStringAsFixed(2)} images/second');
      print('');

      // Performance evaluation
      if (avgTime < 100) {
        print('✅ EXCELLENT performance for mobile ONNX inference!');
      } else if (avgTime < 200) {
        print('✅ GOOD performance for mobile ONNX inference');
      } else if (avgTime < 500) {
        print('⚠️  ACCEPTABLE performance, could be optimized');
      } else {
        print('⚠️  SLOW performance, check model or device');
      }

      print('\n✅ Benchmark complete!');
    });
  });
}

// Helper functions
double _calculateL2Norm(List<double> vector) {
  double sum = 0.0;
  for (final value in vector) {
    sum += value * value;
  }
  return _sqrt(sum);
}

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;

  double dot = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  final denominator = _sqrt(normA) * _sqrt(normB);
  return denominator == 0 ? 0.0 : dot / denominator;
}

double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
