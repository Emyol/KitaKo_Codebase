import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_app/src/services/embedding_service.dart';
import 'package:kitako_app/src/services/image_loader_service.dart';

/// Integration test for image embeddings on real device
/// This test loads actual images from the device gallery and generates embeddings
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Image Embedding Device Tests', () {
    late EmbeddingService embeddingService;
    late ImageLoaderService imageLoader;

    setUp(() async {
      embeddingService = EmbeddingService();
      imageLoader = ImageLoaderService();

      print('\n========================================');
      print('INITIALIZING SERVICES');
      print('========================================');

      final embeddingInit = await embeddingService.initialize();
      final imageLoaderInit = await imageLoader.initialize();

      print('Embedding service initialized: $embeddingInit');
      print('Image loader initialized: $imageLoaderInit');
      print('Text encoder ready: ${embeddingService.isTextReady}');
      print('Image encoder ready: ${embeddingService.isImageReady}');

      final stats = embeddingService.getCacheStats();
      print('Mode: ${stats['mode']}');
      print('========================================\n');

      expect(embeddingInit, isTrue);
      expect(imageLoaderInit, isTrue);
    });

    tearDown(() {
      embeddingService.dispose();
      imageLoader.dispose();
    });

    test('Load images from device gallery', () async {
      print('\n========================================');
      print('LOADING IMAGES FROM DEVICE GALLERY');
      print('========================================\n');

      final images = await imageLoader.loadDeviceImages();

      print('Total images found: ${images.length}');
      print('');

      if (images.isEmpty) {
        print('⚠️  No images found on device!');
        print('Please add some images to your device gallery.');
        return;
      }

      // Show first few images
      final previewCount = images.length < 5 ? images.length : 5;
      print('First $previewCount images:');
      for (int i = 0; i < previewCount; i++) {
        final img = images[i];
        print('  $i. ${img.name}');
        print('     Path: ${img.path}');
        print('     Size: ${img.sizeBytes != null ? '${(img.sizeBytes! / 1024).toStringAsFixed(1)} KB' : 'unknown'}');
        if (img.width != null && img.height != null) {
          print('     Dimensions: ${img.width}x${img.height}');
        }
        print('');
      }

      expect(images, isNotEmpty);
    });

    test('Generate embeddings for device images', () async {
      print('\n========================================');
      print('GENERATING IMAGE EMBEDDINGS');
      print('========================================\n');

      final images = await imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        print('⚠️  No images to process. Skipping test.');
        return;
      }

      final stats = embeddingService.getCacheStats();
      final isRealMode = stats['mode'] == 'real';

      if (!isRealMode) {
        print('⚠️  Running in MOCK mode - image embeddings will be hash-based');
        print('');
      } else {
        print('✅ Running in REAL mode - using ONNX neural network');
        print('');
      }

      // Test with first 3 images (or fewer if less available)
      final testCount = images.length < 3 ? images.length : 3;
      final embeddings = <List<double>>[];
      final times = <int>[];

      print('Processing $testCount images...\n');

      for (int i = 0; i < testCount; i++) {
        final image = images[i];
        print('Image ${i + 1}: ${image.name}');

        try {
          // Load real image bytes via ImageLoaderService (handles Android scoped storage)
          final imageBytes = await imageLoader.getImageBytes(image);
          if (imageBytes == null) {
            print('  ⚠️  Could not load image bytes, skipping');
            continue;
          }
          print('  ✓ Loaded ${imageBytes.length} bytes');

          final stopwatch = Stopwatch()..start();
          final embedding = await embeddingService.generateImageEmbedding(imageBytes);
          stopwatch.stop();

          embeddings.add(embedding);
          times.add(stopwatch.elapsedMilliseconds);

          print('  ✓ Generated in ${stopwatch.elapsedMilliseconds}ms');
          print('  ✓ Dimension: ${embedding.length}');
          print('  ✓ First 5 values: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).toList()}');

          // Calculate L2 norm
          final norm = _calculateL2Norm(embedding);
          print('  ✓ L2 norm: ${norm.toStringAsFixed(6)}');

          // Verify embedding is valid
          expect(embedding.length, EmbeddingService.embeddingDimension);

          if (isRealMode) {
            // In real mode, embeddings should be normalized
            expect(norm, closeTo(1.0, 0.1));
          }

          print('');
        } catch (e) {
          print('  ❌ Error: $e');
          print('');
          rethrow;
        }
      }

      // Calculate statistics
      if (times.isNotEmpty) {
        final avgTime = times.reduce((a, b) => a + b) / times.length;
        final minTime = times.reduce((a, b) => a < b ? a : b);
        final maxTime = times.reduce((a, b) => a > b ? a : b);

        print('--- PERFORMANCE STATISTICS ---');
        print('Images processed: $testCount');
        print('Average time: ${avgTime.toStringAsFixed(2)}ms');
        print('Min time: ${minTime}ms');
        print('Max time: ${maxTime}ms');
        print('');
      }

      // Test embedding uniqueness
      if (embeddings.length >= 2) {
        print('--- UNIQUENESS TEST ---');
        for (int i = 0; i < embeddings.length - 1; i++) {
          for (int j = i + 1; j < embeddings.length; j++) {
            final sim = _cosineSimilarity(embeddings[i], embeddings[j]);
            print('Similarity between image $i and $j: ${sim.toStringAsFixed(4)}');
          }
        }

        if (isRealMode) {
          print('✅ Different images should have different embeddings');
        } else {
          print('⚠️  Mock mode - similarities may not be meaningful');
        }
        print('');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Test image similarity comparison', () async {
      print('\n========================================');
      print('IMAGE SIMILARITY COMPARISON');
      print('========================================\n');

      final images = await imageLoader.loadDeviceImages();

      if (images.length < 3) {
        print('⚠️  Need at least 3 images for similarity test. Skipping.');
        return;
      }

      final stats = embeddingService.getCacheStats();
      final isRealMode = stats['mode'] == 'real';

      if (!isRealMode) {
        print('⚠️  Skipping similarity test - requires REAL mode');
        return;
      }

      print('Testing similarity between multiple images...\n');

      // Generate embeddings for first 3 images using real bytes
      final embeddings = <List<double>>[];

      for (int i = 0; i < 3; i++) {
        final imageBytes = await imageLoader.getImageBytes(images[i]);
        if (imageBytes == null) {
          print('Could not load image $i, skipping');
          continue;
        }
        final embedding = await embeddingService.generateImageEmbedding(imageBytes);
        embeddings.add(embedding);
        print('Generated embedding for image ${i + 1} (${images[i].name})');
      }

      // Compute pairwise similarities
      print('\nSimilarity Matrix:');
      print('           Image 1  Image 2  Image 3');
      for (int i = 0; i < 3; i++) {
        String row = 'Image ${i + 1}   ';
        for (int j = 0; j < 3; j++) {
          final sim = _cosineSimilarity(embeddings[i], embeddings[j]);
          row += '${sim.toStringAsFixed(3)}    ';
        }
        print(row);
      }
      print('');

      print('✅ Image similarity comparison complete');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Performance benchmark on device', () async {
      print('\n========================================');
      print('DEVICE PERFORMANCE BENCHMARK');
      print('========================================\n');

      final images = await imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        print('⚠️  No images to benchmark. Skipping.');
        return;
      }

      final stats = embeddingService.getCacheStats();
      print('Mode: ${stats['mode']}');
      print('Device: Running on physical device/emulator');
      print('');

      // Benchmark image embedding generation using real image
      final firstImage = images.first;
      final imageBytes = await imageLoader.getImageBytes(firstImage);

      if (imageBytes == null) {
        print('⚠️  Could not load image bytes. Skipping benchmark.');
        return;
      }

      print('Benchmarking with: ${firstImage.name} (${imageBytes.length} bytes)\n');

      final iterations = 10;
      final times = <int>[];

      print('Running $iterations iterations...\n');

      for (int i = 0; i < iterations; i++) {
        final stopwatch = Stopwatch()..start();
        await embeddingService.generateImageEmbedding(imageBytes);
        stopwatch.stop();

        times.add(stopwatch.elapsedMilliseconds);
        print('Iteration ${i + 1}: ${stopwatch.elapsedMilliseconds}ms');
      }

      final avgTime = times.reduce((a, b) => a + b) / times.length;
      final minTime = times.reduce((a, b) => a < b ? a : b);
      final maxTime = times.reduce((a, b) => a > b ? a : b);

      // Calculate standard deviation
      final variance = times.map((t) => (t - avgTime) * (t - avgTime)).reduce((a, b) => a + b) / times.length;
      final stdDev = _sqrt(variance);

      print('\n--- RESULTS ---');
      print('Average: ${avgTime.toStringAsFixed(2)}ms');
      print('Min: ${minTime}ms');
      print('Max: ${maxTime}ms');
      print('Std Dev: ${stdDev.toStringAsFixed(2)}ms');
      print('');

      if (stats['mode'] == 'real') {
        print('Expected performance (ONNX on device):');
        print('  - First call: 100-300ms (model warmup)');
        print('  - Subsequent: 50-150ms');
        print('');
      }

      // Performance should be reasonable
      expect(avgTime, lessThan(1000), reason: 'Average should be < 1 second');
    }, timeout: const Timeout(Duration(minutes: 10)));
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
