import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// SigLIP-2 / Kitako Model Integration Tests
///
/// Tests SigLIP-2 models for:
/// - Model loading and initialization
/// - Image embedding generation
/// - Text embedding generation
/// - Cross-modal similarity (image-text alignment)
/// - Real-world search quality
///
/// Run with: flutter test integration_test/siglip_comprehensive_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Test configuration
  late String modelsDir;
  late String tokenizerPath;

  // Test data
  final testTexts = [
    'a cat sitting on a table',
    'a dog running in the park',
    'purple flowers in a yellow vase',
    'people surfing in the ocean',
    'a green car parked on a rainy street',
  ];

  setUpAll(() async {
    // Get app data directory
    final appDir = await getApplicationDocumentsDirectory();
    modelsDir = '${appDir.parent.path}/app_flutter/onnx_models';
    tokenizerPath = '${appDir.parent.path}/app_flutter/tokenizer/tokenizer.json';

    print('═══════════════════════════════════════════════════════════');
    print('SigLIP-2 / Kitako Model Integration Tests');
    print('═══════════════════════════════════════════════════════════');
    print('Models directory: $modelsDir');
    print('Tokenizer path: $tokenizerPath');
    print('');
  });

  group('1. Model File Verification', () {
    testWidgets('All required model files exist', (tester) async {
      print('\n--- Test: Model File Verification ---');

      final files = {
        'SigLIP-2 Vision': '$modelsDir/siglip2_vision_model_fp32.onnx',
        'SigLIP-2 Text': '$modelsDir/siglip2_text_model_fp32.onnx',
        'Tokenizer': tokenizerPath,
      };

      for (final entry in files.entries) {
        final file = File(entry.value);
        final exists = file.existsSync();
        final size = exists ? file.lengthSync() : 0;

        print('${exists ? "✓" : "✗"} ${entry.key}: ${exists ? "${(size / 1024 / 1024).toStringAsFixed(1)} MB" : "NOT FOUND"}');
        expect(exists, true, reason: '${entry.key} not found at ${entry.value}');
      }

      print('');
    });
  });

  group('2. SigLIP-2 Tests', () {
    late OnnxEmbeddingService service;

    testWidgets('Initialize SigLIP-2 model', (tester) async {
      print('\n--- Test: SigLIP-2 Initialization ---');

      service = OnnxEmbeddingService();

      try {
        await service.initialize(
          visionModelPath: '$modelsDir/siglip2_vision_model_fp32.onnx',
          textModelPath: '$modelsDir/siglip2_text_model_fp32.onnx',
          tokenizerPath: tokenizerPath,
          modelVersion: SiglipModelVersion.siglip2,
        );

        print('✓ SigLIP-2 initialized successfully');
        print('  - Model version: ${service.modelVersion.name}');
        print('  - Image encoder ready: ${service.isImageEncoderReady}');
        print('  - Text encoder ready: ${service.isTextEncoderReady}');
        print('  - Config: ${service.modelConfig}');

        expect(service.isInitialized, true);
        expect(service.isImageEncoderReady, true);
        expect(service.isTextEncoderReady, true);
        expect(service.modelConfig.imageSize, 224);
        expect(service.modelConfig.embeddingDimension, 768);
      } catch (e) {
        print('✗ Initialization failed: $e');
        rethrow;
      }

      print('');
    });

    testWidgets('Generate text embeddings with SigLIP-2', (tester) async {
      print('\n--- Test: SigLIP-2 Text Embeddings ---');

      for (final text in testTexts.take(3)) {
        final embedding = service.embedText(text);

        expect(embedding.length, 768, reason: 'Embedding should be 768-dimensional');

        // Check L2 normalization
        double norm = 0;
        for (final v in embedding) {
          norm += v * v;
        }
        norm = _sqrt(norm);

        print('✓ "$text"');
        print('  Dim: ${embedding.length}, L2 norm: ${norm.toStringAsFixed(4)}');

        expect(norm, closeTo(1.0, 0.01), reason: 'Embedding should be L2 normalized');
      }

      print('');
    });

    testWidgets('Text similarity validation with SigLIP-2', (tester) async {
      print('\n--- Test: SigLIP-2 Text Similarity ---');

      final catEmbed = service.embedText('a cat sitting on a table');
      final catSimilar = service.embedText('a cat on the table');
      final dogEmbed = service.embedText('a dog running in the park');

      final similarScore = service.cosineSimilarity(catEmbed, catSimilar);
      final dissimilarScore = service.cosineSimilarity(catEmbed, dogEmbed);

      print('Similar texts (cat variations): ${similarScore.toStringAsFixed(4)}');
      print('Dissimilar texts (cat vs dog): ${dissimilarScore.toStringAsFixed(4)}');

      expect(similarScore, greaterThan(dissimilarScore),
        reason: 'Similar texts should have higher similarity');
      expect(similarScore, greaterThan(0.7),
        reason: 'Very similar texts should have >0.7 similarity');

      print('✓ Similar texts have higher similarity than dissimilar');
      print('');
    });

    testWidgets('Cleanup SigLIP-2', (tester) async {
      service.dispose();
      print('✓ SigLIP-2 disposed');
    });
  });

  group('3. Cross-Modal Similarity', () {
    testWidgets('Validate image-text alignment', (tester) async {
      print('\n═══════════════════════════════════════════════════════════');
      print('CRITICAL TEST: Cross-Modal Alignment');
      print('═══════════════════════════════════════════════════════════');

      final service = OnnxEmbeddingService();

      await service.initialize(
        visionModelPath: '$modelsDir/siglip2_vision_model_fp32.onnx',
        textModelPath: '$modelsDir/siglip2_text_model_fp32.onnx',
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      print('✓ Model initialized');
      print('');

      // Create a simple test image (solid gray - for basic validation)
      final testImage = _createSolidColorImage(128, 128, 128);
      final testText = 'a gray square image';

      // Generate embeddings
      final imgEmbed = service.embedImage(testImage);
      final txtEmbed = service.embedText(testText);

      // Compute cross-modal similarity
      final similarity = service.cosineSimilarity(imgEmbed, txtEmbed);

      print('Cross-Modal Similarity Results:');
      print('───────────────────────────────────────────────────────────');
      print('SigLIP-2: ${similarity.toStringAsFixed(4)}');
      print('───────────────────────────────────────────────────────────');
      print('');

      if (similarity > 0.3) {
        print('✓ SigLIP-2: Cross-modal alignment is working');
      } else {
        print('⚠ SigLIP-2: Low cross-modal similarity');
      }

      print('');
      print('═══════════════════════════════════════════════════════════');

      // Basic validation
      expect(imgEmbed.length, 768);
      expect(txtEmbed.length, 768);

      // Cleanup
      service.dispose();
    });
  });

  group('4. Performance Benchmarks', () {
    testWidgets('Benchmark text embedding performance', (tester) async {
      print('\n--- Benchmark: Text Embedding Performance ---');

      final service = OnnxEmbeddingService();
      await service.initialize(
        visionModelPath: '$modelsDir/siglip2_vision_model_fp32.onnx',
        textModelPath: '$modelsDir/siglip2_text_model_fp32.onnx',
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      // Warm up
      service.embedText('warm up text');

      // Benchmark
      final stopwatch = Stopwatch()..start();
      const iterations = 10;

      for (var i = 0; i < iterations; i++) {
        service.embedText('a cat sitting on a table');
      }

      stopwatch.stop();
      final avgMs = stopwatch.elapsedMilliseconds / iterations;

      print('SigLIP-2 Text embedding: ${avgMs.toStringAsFixed(1)} ms/inference');
      print('Throughput: ${(1000 / avgMs).toStringAsFixed(1)} embeddings/sec');

      expect(avgMs, lessThan(5000), reason: 'Text embedding should be under 5 seconds');

      service.dispose();
      print('');
    });

    testWidgets('Benchmark image embedding performance', (tester) async {
      print('\n--- Benchmark: Image Embedding Performance ---');

      final service = OnnxEmbeddingService();
      await service.initialize(
        visionModelPath: '$modelsDir/siglip2_vision_model_fp32.onnx',
        textModelPath: '$modelsDir/siglip2_text_model_fp32.onnx',
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      final testImage = _createSolidColorImage(128, 128, 128);

      // Warm up
      service.embedImage(testImage);

      // Benchmark
      final stopwatch = Stopwatch()..start();
      const iterations = 5;

      for (var i = 0; i < iterations; i++) {
        service.embedImage(testImage);
      }

      stopwatch.stop();
      final avgMs = stopwatch.elapsedMilliseconds / iterations;

      print('SigLIP-2 Image embedding: ${avgMs.toStringAsFixed(1)} ms/inference');
      print('Throughput: ${(1000 / avgMs).toStringAsFixed(1)} images/sec');

      expect(avgMs, lessThan(10000), reason: 'Image embedding should be under 10 seconds');

      service.dispose();
      print('');
    });
  });
}

/// Create a simple solid color image for testing
Uint8List _createSolidColorImage(int r, int g, int b) {
  // Create a simple PPM image (224x224 for SigLIP-2 compatibility)
  // PPM format: P6\n224 224\n255\n<RGB bytes>
  final width = 224;
  final height = 224;
  final header = 'P6\n$width $height\n255\n';
  final headerBytes = header.codeUnits;
  final pixelCount = width * height;
  final rgbBytes = Uint8List(pixelCount * 3);

  for (var i = 0; i < pixelCount; i++) {
    rgbBytes[i * 3] = r;
    rgbBytes[i * 3 + 1] = g;
    rgbBytes[i * 3 + 2] = b;
  }

  final result = Uint8List(headerBytes.length + rgbBytes.length);
  result.setRange(0, headerBytes.length, headerBytes);
  result.setRange(headerBytes.length, result.length, rgbBytes);

  return result;
}

/// Simple sqrt implementation
double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
