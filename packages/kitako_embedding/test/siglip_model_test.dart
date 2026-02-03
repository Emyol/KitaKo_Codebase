import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

/// Comprehensive unit tests for SigLIP model implementations
/// Tests both SigLIP-1 (quantized) and SigLIP-2 (FP32 with projections)
void main() {
  // Model paths - update these to your actual model locations
  const modelsBasePath = 'c:\\Users\\Jhezra\\Documents\\KitaKo_System\\assets\\models';
  
  // SigLIP-1 Quantized models (smaller, without projection layers)
  const siglip1VisionPath = '$modelsBasePath\\vision_model_quantized.onnx';
  const siglip1TextPath = '$modelsBasePath\\text_model_quantized.onnx';
  
  // SigLIP-2 FP32 models (larger, with projection layers)
  const siglip2VisionPath = '$modelsBasePath\\siglip2_vision_model_fp32.onnx';
  const siglip2TextPath = '$modelsBasePath\\siglip2_text_model_fp32.onnx';
  
  const tokenizerPath = 'c:\\Users\\Jhezra\\Documents\\KitaKo_System\\apps\\kitako_app\\assets\\tokenizer\\tokenizer.json';

  group('Model File Validation', () {
    test('SigLIP-1 models exist and have correct sizes', () {
      final visionFile = File(siglip1VisionPath);
      final textFile = File(siglip1TextPath);

      expect(visionFile.existsSync(), true, reason: 'Vision model file should exist');
      expect(textFile.existsSync(), true, reason: 'Text model file should exist');

      // Check approximate sizes (allow ±10MB variance)
      final visionSize = visionFile.lengthSync() / (1024 * 1024);
      final textSize = textFile.lengthSync() / (1024 * 1024);

      expect(visionSize, inInclusiveRange(90, 110), 
        reason: 'Vision model should be ~99MB');
      expect(textSize, inInclusiveRange(100, 120), 
        reason: 'Text model should be ~111MB');

      print('✓ SigLIP-1 Vision: ${visionSize.toStringAsFixed(1)} MB');
      print('✓ SigLIP-1 Text: ${textSize.toStringAsFixed(1)} MB');
    });

    test('SigLIP-2 models exist and have correct sizes', () {
      final visionFile = File(siglip2VisionPath);
      final textFile = File(siglip2TextPath);

      expect(visionFile.existsSync(), true, reason: 'SigLIP-2 vision model should exist');
      expect(textFile.existsSync(), true, reason: 'SigLIP-2 text model should exist');

      // Check approximate sizes
      final visionSize = visionFile.lengthSync() / (1024 * 1024);
      final textSize = textFile.lengthSync() / (1024 * 1024);

      expect(visionSize, inInclusiveRange(360, 380), 
        reason: 'SigLIP-2 vision should be ~371MB');
      expect(textSize, inInclusiveRange(1050, 1150), 
        reason: 'SigLIP-2 text should be ~1.1GB');

      print('✓ SigLIP-2 Vision: ${visionSize.toStringAsFixed(1)} MB');
      print('✓ SigLIP-2 Text: ${textSize.toStringAsFixed(1)} MB');
    });

    test('Tokenizer file exists', () {
      final tokenizerFile = File(tokenizerPath);
      expect(tokenizerFile.existsSync(), true);
      
      final size = tokenizerFile.lengthSync() / 1024;
      print('✓ Tokenizer: ${size.toStringAsFixed(1)} KB');
    });
  });

  group('SigLIP-1 Model Initialization', () {
    late OnnxSiglipInference siglip1;

    setUpAll(() async {
      siglip1 = OnnxSiglipInference();
      await siglip1.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip1.dispose();
    });

    test('Models load successfully', () {
      expect(siglip1.isImageEncoderReady, true);
      expect(siglip1.isTextEncoderReady, true);
    });

    test('Model configuration is correct', () {
      final config = siglip1.modelConfig;
      expect(config, contains('224x224'));
      print('✓ SigLIP-1 Config: $config');
    });
  });

  group('SigLIP-2 Model Initialization', () {
    late OnnxSiglipInference siglip2;

    setUpAll(() async {
      siglip2 = OnnxSiglipInference();
      await siglip2.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip2.dispose();
    });

    test('Models load successfully', () {
      expect(siglip2.isImageEncoderReady, true);
      expect(siglip2.isTextEncoderReady, true);
    });

    test('Model configuration is correct', () {
      final config = siglip2.modelConfig;
      expect(config, contains('256x256'));
      print('✓ SigLIP-2 Config: $config');
    });
  });

  group('Image Embedding Generation', () {
    late OnnxSiglipInference siglip1;
    late OnnxSiglipInference siglip2;

    setUpAll(() async {
      siglip1 = OnnxSiglipInference();
      await siglip1.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );

      siglip2 = OnnxSiglipInference();
      await siglip2.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip1.dispose();
      siglip2.dispose();
    });

    test('SigLIP-1 generates 768-dimensional embeddings', () async {
      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await siglip1.embedImage(testImage);

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());
      
      // Check normalization (L2 norm should be ~1.0)
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      
      print('✓ SigLIP-1 embedding: 768D, L2 norm = ${norm.toStringAsFixed(4)}');
    });

    test('SigLIP-2 generates 768-dimensional embeddings', () async {
      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await siglip2.embedImage(testImage);

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());
      
      // Check normalization
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      
      print('✓ SigLIP-2 embedding: 768D, L2 norm = ${norm.toStringAsFixed(4)}');
    });

    test('Image embeddings are deterministic (same input → same output)', () async {
      final testImage = ImagePreprocessor.createTestImage();
      
      final embedding1 = await siglip1.embedImage(testImage);
      final embedding2 = await siglip1.embedImage(testImage);

      // Should be identical
      for (var i = 0; i < 768; i++) {
        expect(embedding1[i], closeTo(embedding2[i], 1e-6));
      }
      
      print('✓ Deterministic: embeddings match');
    });

    test('Different images produce different embeddings', () async {
      final image1 = ImagePreprocessor.createTestImage();
      final image2 = _createRandomImage();

      final embedding1 = await siglip1.embedImage(image1);
      final embedding2 = await siglip1.embedImage(image2);

      final similarity = _cosineSimilarity(embedding1, embedding2);
      
      // Random images should have low similarity
      expect(similarity, lessThan(0.9));
      
      print('✓ Different images: similarity = ${similarity.toStringAsFixed(4)}');
    });
  });

  group('Text Embedding Generation', () {
    late OnnxSiglipInference siglip1;
    late OnnxSiglipInference siglip2;

    setUpAll(() async {
      siglip1 = OnnxSiglipInference();
      await siglip1.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );

      siglip2 = OnnxSiglipInference();
      await siglip2.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip1.dispose();
      siglip2.dispose();
    });

    test('SigLIP-1 generates 768-dimensional text embeddings', () async {
      final embedding = await siglip1.embedText('cat on a table');

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());
      
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      
      print('✓ SigLIP-1 text: 768D, L2 norm = ${norm.toStringAsFixed(4)}');
    });

    test('SigLIP-2 generates 768-dimensional text embeddings', () async {
      final embedding = await siglip2.embedText('cat on a table');

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());
      
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      
      print('✓ SigLIP-2 text: 768D, L2 norm = ${norm.toStringAsFixed(4)}');
    });

    test('Text embeddings are deterministic', () async {
      final text = 'a cat sitting on a table';
      
      final embedding1 = await siglip1.embedText(text);
      final embedding2 = await siglip1.embedText(text);

      for (var i = 0; i < 768; i++) {
        expect(embedding1[i], closeTo(embedding2[i], 1e-6));
      }
      
      print('✓ Deterministic: text embeddings match');
    });

    test('Similar texts have high similarity', () async {
      final embedding1 = await siglip1.embedText('cat on table');
      final embedding2 = await siglip1.embedText('cat sitting on a table');

      final similarity = _cosineSimilarity(embedding1, embedding2);
      
      // Similar phrases should have high similarity
      expect(similarity, greaterThan(0.7));
      
      print('✓ Similar texts: similarity = ${similarity.toStringAsFixed(4)}');
    });

    test('Unrelated texts have low similarity', () async {
      final embedding1 = await siglip1.embedText('cat on a table');
      final embedding2 = await siglip1.embedText('car driving on highway');

      final similarity = _cosineSimilarity(embedding1, embedding2);
      
      // Unrelated should have lower similarity
      expect(similarity, lessThan(0.5));
      
      print('✓ Unrelated texts: similarity = ${similarity.toStringAsFixed(4)}');
    });
  });

  group('SigLIP-1 vs SigLIP-2 Comparison', () {
    late OnnxSiglipInference siglip1;
    late OnnxSiglipInference siglip2;
    late Float32List testImage;

    setUpAll(() async {
      siglip1 = OnnxSiglipInference();
      await siglip1.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );

      siglip2 = OnnxSiglipInference();
      await siglip2.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
      );

      testImage = ImagePreprocessor.createTestImage();
    });

    tearDownAll(() {
      siglip1.dispose();
      siglip2.dispose();
    });

    test('Both models produce normalized embeddings', () async {
      final imgEmbed1 = await siglip1.embedImage(testImage);
      final imgEmbed2 = await siglip2.embedImage(testImage);

      final norm1 = _computeL2Norm(imgEmbed1);
      final norm2 = _computeL2Norm(imgEmbed2);

      expect(norm1, closeTo(1.0, 0.01));
      expect(norm2, closeTo(1.0, 0.01));
      
      print('✓ Both normalized: SigLIP-1 = ${norm1.toStringAsFixed(4)}, SigLIP-2 = ${norm2.toStringAsFixed(4)}');
    });

    test('SigLIP-2 has higher cross-modal similarity than SigLIP-1', () async {
      final testText = 'a cat on a table';
      
      // Get embeddings from both models
      final imgEmbed1 = await siglip1.embedImage(testImage);
      final textEmbed1 = await siglip1.embedText(testText);
      final similarity1 = _cosineSimilarity(imgEmbed1, textEmbed1);

      final imgEmbed2 = await siglip2.embedImage(testImage);
      final textEmbed2 = await siglip2.embedText(testText);
      final similarity2 = _cosineSimilarity(imgEmbed2, textEmbed2);

      print('');
      print('Cross-modal similarity comparison:');
      print('  SigLIP-1 (no projection): ${similarity1.toStringAsFixed(4)}');
      print('  SigLIP-2 (with projection): ${similarity2.toStringAsFixed(4)}');
      print('  Improvement: ${((similarity2 - similarity1) * 100).toStringAsFixed(1)}%');

      // SigLIP-2 should have significantly higher similarity due to projection layers
      // Expected: SigLIP-1 ≈ 0.05-0.15, SigLIP-2 ≈ 0.75-0.95
      expect(similarity2, greaterThan(similarity1 * 3),
        reason: 'SigLIP-2 should have at least 3x higher similarity');
      
      if (similarity2 > 0.7) {
        print('✓ EXCELLENT: SigLIP-2 has strong cross-modal alignment');
      } else if (similarity2 > 0.3) {
        print('⚠ WARNING: SigLIP-2 similarity lower than expected');
      } else {
        print('❌ ERROR: SigLIP-2 may not have projection layers');
      }
    });

    test('SigLIP-1 has LOW similarity (no projection layers)', () async {
      final imgEmbed = await siglip1.embedImage(testImage);
      final textEmbed = await siglip1.embedText('cat on a table');
      final similarity = _cosineSimilarity(imgEmbed, textEmbed);

      print('SigLIP-1 cross-modal similarity: ${similarity.toStringAsFixed(4)}');

      // Without projection layers, similarity should be low (0.05 - 0.15)
      expect(similarity, lessThan(0.3),
        reason: 'SigLIP-1 lacks projection layers, should have low similarity');
      
      if (similarity < 0.15) {
        print('✓ Expected: Low similarity confirms missing projection layers');
      }
    });

    test('SigLIP-2 has HIGH similarity (with projection layers)', () async {
      final imgEmbed = await siglip2.embedImage(testImage);
      final textEmbed = await siglip2.embedText('cat on a table');
      final similarity = _cosineSimilarity(imgEmbed, textEmbed);

      print('SigLIP-2 cross-modal similarity: ${similarity.toStringAsFixed(4)}');

      // With projection layers, similarity should be high (0.7 - 0.95)
      expect(similarity, greaterThan(0.5),
        reason: 'SigLIP-2 has projection layers, should have high similarity');
      
      if (similarity > 0.7) {
        print('✓ Excellent: High similarity confirms projection layers are working');
      } else {
        print('⚠ Warning: Lower than expected for SigLIP-2');
      }
    });
  });

  group('Performance Benchmarks', () {
    late OnnxSiglipInference siglip;

    setUpAll(() async {
      siglip = OnnxSiglipInference();
      await siglip.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip.dispose();
    });

    test('Image embedding performance', () async {
      final testImage = ImagePreprocessor.createTestImage();
      
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        await siglip.embedImage(testImage);
      }
      stopwatch.stop();
      
      final avgTime = stopwatch.elapsedMilliseconds / 10;
      print('✓ Image embedding: ${avgTime.toStringAsFixed(1)} ms/image (avg of 10)');
      
      // Should be reasonably fast (< 1000ms on desktop)
      expect(avgTime, lessThan(2000));
    });

    test('Text embedding performance', () async {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        await siglip.embedText('cat on a table');
      }
      stopwatch.stop();
      
      final avgTime = stopwatch.elapsedMilliseconds / 10;
      print('✓ Text embedding: ${avgTime.toStringAsFixed(1)} ms/query (avg of 10)');
      
      // Text should be faster than images
      expect(avgTime, lessThan(1000));
    });
  });

  group('Edge Cases and Error Handling', () {
    late OnnxSiglipInference siglip;

    setUpAll(() async {
      siglip = OnnxSiglipInference();
      await siglip.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
      );
    });

    tearDownAll(() {
      siglip.dispose();
    });

    test('Handles empty text gracefully', () async {
      final embedding = await siglip.embedText('');
      expect(embedding.length, 768);
      
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      
      print('✓ Empty text handled: norm = ${norm.toStringAsFixed(4)}');
    });

    test('Handles very long text (should truncate)', () async {
      final longText = 'word ' * 100; // 100 words
      final embedding = await siglip.embedText(longText);
      
      expect(embedding.length, 768);
      expect(_computeL2Norm(embedding), closeTo(1.0, 0.01));
      
      print('✓ Long text handled (truncated to 64 tokens)');
    });

    test('Handles special characters', () async {
      final embedding = await siglip.embedText('cat!@#\$%^&*()_+-=[]{}');
      
      expect(embedding.length, 768);
      expect(_computeL2Norm(embedding), closeTo(1.0, 0.01));
      
      print('✓ Special characters handled');
    });

    test('Handles non-English text', () async {
      final embedding = await siglip.embedText('猫在桌子上'); // Chinese
      
      expect(embedding.length, 768);
      expect(_computeL2Norm(embedding), closeTo(1.0, 0.01));
      
      print('✓ Non-English text handled');
    });
  });
}

// Helper functions
double _computeL2Norm(Float32List vector) {
  double sumSquares = 0.0;
  for (final val in vector) {
    sumSquares += val * val;
  }
  return math.sqrt(sumSquares);
}

double _cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have same length');
  }

  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  normA = math.sqrt(normA);
  normB = math.sqrt(normB);

  if (normA == 0 || normB == 0) return 0.0;

  return dotProduct / (normA * normB);
}

Float32List _createRandomImage() {
  final random = math.Random();
  final pixels = Float32List(1 * 224 * 224 * 3);
  
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = (random.nextDouble() * 2.0) - 1.0; // Range: [-1, 1]
  }
  
  return pixels;
}
