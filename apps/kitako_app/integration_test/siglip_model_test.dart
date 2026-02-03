import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_app/main.dart' as app;
import 'package:kitako_embedding/kitako_embedding.dart';

/// Integration test for SigLIP models on Android emulator/device
/// 
/// Run with: flutter test integration_test/siglip_model_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SigLIP Model Integration Tests', () {
    testWidgets('SigLIP-1 ALIGNED vs SigLIP-2 Cross-Modal Similarity',
        (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('CRITICAL TEST: Cross-Modal Similarity Comparison');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      print('This test validates whether projection layers are working');
      print('by comparing image-text similarity across both models.');
      print('');

      // Initialize SigLIP-1 ALIGNED service
      final service1 = OnnxEmbeddingService();
      try {
        await service1.initialize(
          visionModelPath:
              '/data/data/com.example.kitako_app/app_flutter/onnx_models/siglip_vision_aligned_full.onnx',
          textModelPath:
              '/data/data/com.example.kitako_app/app_flutter/onnx_models/siglip_text_aligned_full.onnx',
          tokenizerPath:
              '/data/data/com.example.kitako_app/app_flutter/tokenizer/tokenizer.json',
          modelVersion: SiglipModelVersion.siglip1,
        );
        print('✓ SigLIP-1 ALIGNED initialized');
      } catch (e) {
        print('✗ Failed to initialize SigLIP-1: $e');
        print('');
        print('Make sure models are deployed to device:');
        print('  adb push siglip_vision_aligned_full.onnx /data/local/tmp/');
        print('  adb push siglip_text_aligned_full.onnx /data/local/tmp/');
        print('  adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip_vision_aligned_full.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/');
        print('  adb shell run-as com.example.kitako_app cp /data/local/tmp/siglip_text_aligned_full.onnx /data/data/com.example.kitako_app/app_flutter/onnx_models/');
        rethrow;
      }

      // Initialize SigLIP-2 service
      final service2 = OnnxEmbeddingService();
      try {
        await service2.initialize(
          visionModelPath:
              '/data/data/com.example.kitako_app/app_flutter/onnx_models/siglip2_vision_model_fp32.onnx',
          textModelPath:
              '/data/data/com.example.kitako_app/app_flutter/onnx_models/siglip2_text_model_fp32.onnx',
          tokenizerPath:
              '/data/data/com.example.kitako_app/app_flutter/tokenizer/tokenizer.json',
          modelVersion: SiglipModelVersion.siglip2,
        );
        print('✓ SigLIP-2 initialized');
      } catch (e) {
        print('✗ Failed to initialize SigLIP-2: $e');
        print('');
        print('Run setup script first:');
        print('  .\\apps\\kitako_app\\setup_siglip2.ps1');
        rethrow;
      }

      // Create test image (simple solid color)
      final testImage = _createTestImage();
      final testText = 'cat on a table';

      print('');
      print('Generating embeddings...');

      // Get embeddings from SigLIP-1 ALIGNED
      final imgEmbed1 = service1.embedImage(testImage);
      final textEmbed1 = service1.embedText(testText);

      // Get embeddings from SigLIP-2
      final imgEmbed2 = service2.embedImage(testImage);
      final textEmbed2 = service2.embedText(testText);

      // Compute cross-modal similarities
      final similarity1 = _cosineSimilarity(imgEmbed1, textEmbed1);
      final similarity2 = _cosineSimilarity(imgEmbed2, textEmbed2);

      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('RESULTS:');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      print('SigLIP-1 ALIGNED: ${similarity1.toStringAsFixed(4)}');
      print('SigLIP-2: ${similarity2.toStringAsFixed(4)}');
      print('Improvement: ${((similarity2 / similarity1 - 1) * 100).toStringAsFixed(1)}%');
      print('');

      // Interpret results
      if (similarity1 > 0.5) {
        print('✓ GOOD: SigLIP-1 ALIGNED has reasonable similarity');
        print('  (These models have projection layers and should work well)');
      } else {
        print('⚠ WARNING: SigLIP-1 ALIGNED similarity is low');
        print('  (May indicate wrong models or misalignment)');
      }
      print('');

      if (similarity2 > 0.7) {
        print('✓ EXCELLENT: SigLIP-2 has HIGH similarity');
        print('  (Projection layers are working correctly!)');
      } else if (similarity2 > 0.5) {
        print('✓ GOOD: SigLIP-2 has decent similarity');
        print('  (Projection layers are present but may need tuning)');
      } else {
        print('✗ FAILED: SigLIP-2 similarity is too low');
        print('  (Wrong models or projection layers not working)');
      }
      print('');

      if (similarity2 > similarity1 * 1.2) {
        print('✓ SigLIP-2 is better than SigLIP-1 ALIGNED');
      } else if (similarity1 > similarity2) {
        print('⚠ SigLIP-1 ALIGNED performs better - unexpected!');
      } else {
        print('≈ Both models have similar performance');
      }

      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');

      // Test assertions
      expect(imgEmbed1.length, 768, reason: 'SigLIP-1 should output 768D embeddings');
      expect(textEmbed1.length, 768, reason: 'SigLIP-1 should output 768D embeddings');
      expect(imgEmbed2.length, 768, reason: 'SigLIP-2 should output 768D embeddings');
      expect(textEmbed2.length, 768, reason: 'SigLIP-2 should output 768D embeddings');

      // Both models should have reasonable cross-modal alignment
      expect(similarity1, greaterThan(0.3),
          reason: 'SigLIP-1 ALIGNED should have some cross-modal similarity');
      expect(similarity2, greaterThan(0.5),
          reason: 'SigLIP-2 should have good cross-modal similarity (projection layers working)');

      // Cleanup
      service1.dispose();
      service2.dispose();
    });
  });
}

/// Helper: Create a simple test image (solid gray)
Uint8List _createTestImage() {
  // Create a 256x256 RGB image
  final imageSize = 256;
  final pixels = Uint8List(imageSize * imageSize * 3);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = 128; // gray
  }
  return pixels;
}

/// Helper: Compute cosine similarity between two vectors
double _cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have the same length');
  }

  double dotProduct = 0.0;
  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
  }

  // Embeddings are L2-normalized, so cosine similarity = dot product
  return dotProduct;
}
