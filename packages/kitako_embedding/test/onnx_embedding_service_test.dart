import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/src/onnx_embedding_service.dart';
import 'package:kitako_embedding/src/siglip_model_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Model paths - using simplified paths to avoid encoding issues in tests
  // Use forward slashes for ONNX Runtime compatibility
  final testDir = 'C:/temp/onnx_test';
  
  // SigLIP-1 ALIGNED paths (copied from assets/models/onnx/)
  final siglip1VisionPath = '$testDir/vision.onnx';
  final siglip1TextPath = '$testDir/text.onnx';
  final tokenizerPath = 'C:/Users/Jhezra/Documents/KitaKo_System/apps/kitako_app/assets/tokenizer/tokenizer.json';
  
  // SigLIP-2 paths  
  final assetsDir = 'C:/Users/Jhezra/Documents/KitaKo_System/assets/models';
  final siglip2VisionPath = '$assetsDir/siglip2_vision_model_fp32.onnx';
  final siglip2TextPath = '$assetsDir/siglip2_text_model_fp32.onnx';

  /// Helper: Compute L2 norm of a vector
  double _computeL2Norm(Float32List vector) {
    double sum = 0.0;
    for (var v in vector) {
      sum += v * v;
    }
    return sqrt(sum);
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
    
    return dotProduct; // Already normalized, so cosine similarity = dot product
  }

  /// Helper: Create a simple test image (solid color)
  Uint8List _createTestImage() {
    // Create a 256x256 RGB image (solid gray)
    final imageSize = 256;
    final pixels = Uint8List(imageSize * imageSize * 3);
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = 128; // gray
    }
    return pixels;
  }

  group('Model File Validation', () {
    test('SigLIP-1 model files exist', () {
      expect(File(siglip1VisionPath).existsSync(), true, 
        reason: 'Vision model not found at $siglip1VisionPath');
      expect(File(siglip1TextPath).existsSync(), true,
        reason: 'Text model not found at $siglip1TextPath');
      expect(File(tokenizerPath).existsSync(), true,
        reason: 'Tokenizer not found at $tokenizerPath');
      
      print('✓ SigLIP-1 files exist');
    });

    test('SigLIP-2 model files exist', () {
      expect(File(siglip2VisionPath).existsSync(), true,
        reason: 'Vision model not found at $siglip2VisionPath');
      expect(File(siglip2TextPath).existsSync(), true,
        reason: 'Text model not found at $siglip2TextPath');
      
      print('✓ SigLIP-2 files exist');
    });

    test('Model files have expected sizes', () {
      final vision1Size = File(siglip1VisionPath).lengthSync();
      final text1Size = File(siglip1TextPath).lengthSync();
      final vision2Size = File(siglip2VisionPath).lengthSync();
      final text2Size = File(siglip2TextPath).lengthSync();

      // SigLIP-1 ALIGNED (FP32) should be ~354MB + ~421MB = ~775MB
      expect(vision1Size, greaterThan(350 * 1024 * 1024)); // >350MB
      expect(text1Size, greaterThan(400 * 1024 * 1024)); // >400MB

      // SigLIP-2 FP32 should be ~371MB + ~1.1GB = ~1.5GB
      expect(vision2Size, greaterThan(350 * 1024 * 1024)); // >350MB
      expect(text2Size, greaterThan(1000 * 1024 * 1024)); // >1GB

      print('✓ SigLIP-1 ALIGNED: Vision ${(vision1Size / 1024 / 1024).toStringAsFixed(1)}MB, '
            'Text ${(text1Size / 1024 / 1024).toStringAsFixed(1)}MB');
      print('✓ SigLIP-2: Vision ${(vision2Size / 1024 / 1024).toStringAsFixed(1)}MB, '
            'Text ${(text2Size / 1024 / 1024).toStringAsFixed(1)}MB');
    });
  });

  group('SigLIP-1 Initialization', () {
    late OnnxEmbeddingService service;

    setUp(() {
      service = OnnxEmbeddingService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Initializes successfully with SigLIP-1', () async {
      await service.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip1,
      );

      expect(service.isInitialized, true);
      expect(service.isImageEncoderReady, true);
      expect(service.isTextEncoderReady, true);
      
      print('✓ SigLIP-1 initialized');
    });

    test('Reports correct model configuration', () async {
      await service.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip1,
      );

      final config = service.modelConfig;
      expect(config.version, SiglipModelVersion.siglip1);
      expect(config.imageSize, 224);
      expect(config.embeddingDimension, 768);
      expect(config.vocabularySize, 32000);
      
      print('✓ SigLIP-1 config: ${config.imageSize}x${config.imageSize}, '
            '${config.vocabularySize} vocab, ${config.embeddingDimension}D');
    });
  });

  group('SigLIP-2 Initialization', () {
    late OnnxEmbeddingService service;

    setUp(() {
      service = OnnxEmbeddingService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Initializes successfully with SigLIP-2', () async {
      await service.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      expect(service.isInitialized, true);
      expect(service.isImageEncoderReady, true);
      expect(service.isTextEncoderReady, true);
      
      print('✓ SigLIP-2 initialized');
    });

    test('Reports correct model configuration', () async {
      await service.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      final config = service.modelConfig;
      expect(config.version, SiglipModelVersion.siglip2);
      expect(config.imageSize, 256);
      expect(config.embeddingDimension, 768);
      expect(config.vocabularySize, 256000);
      
      print('✓ SigLIP-2 config: ${config.imageSize}x${config.imageSize}, '
            '${config.vocabularySize} vocab, ${config.embeddingDimension}D');
    });
  });

  group('Cross-Modal Similarity Comparison', () {
    test('SigLIP-1 vs SigLIP-2 projection layer validation', () async {
      // Initialize SigLIP-1
      final service1 = OnnxEmbeddingService();
      await service1.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip1,
      );

      // Initialize SigLIP-2
      final service2 = OnnxEmbeddingService();
      await service2.initialize(
        visionModelPath: siglip2VisionPath,
        textModelPath: siglip2TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      // Create test image
      final testImage = _createTestImage();
      final testText = 'cat on a table';

      // Get embeddings from both models
      final imgEmbed1 = service1.embedImage(testImage);
      final textEmbed1 = service1.embedText(testText);
      final imgEmbed2 = service2.embedImage(testImage);
      final textEmbed2 = service2.embedText(testText);

      // Compute cross-modal similarities
      final similarity1 = _cosineSimilarity(imgEmbed1, textEmbed1);
      final similarity2 = _cosineSimilarity(imgEmbed2, textEmbed2);

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('CRITICAL TEST: Cross-Modal Similarity');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      print('SigLIP-1 (no projection): ${similarity1.toStringAsFixed(4)}');
      print('SigLIP-2 (with projection): ${similarity2.toStringAsFixed(4)}');
      print('Improvement: ${((similarity2 / similarity1 - 1) * 100).toStringAsFixed(1)}%');
      print('');

      // CRITICAL VALIDATION:
      // - SigLIP-1 should have LOW similarity (0.05-0.15) - no projection layers
      // - SigLIP-2 should have HIGH similarity (0.75-0.95) - has projection layers
      // - SigLIP-2 should be significantly better (5-10x improvement)

      if (similarity1 < 0.2) {
        print('✓ EXCELLENT: SigLIP-1 has low similarity (no projection layers)');
      } else {
        print('⚠ WARNING: SigLIP-1 similarity higher than expected');
      }

      if (similarity2 > 0.7) {
        print('✓ EXCELLENT: SigLIP-2 has high similarity (projection layers working)');
      } else {
        print('✗ FAILED: SigLIP-2 similarity too low - projection layers may not be working!');
      }

      if (similarity2 > similarity1 * 3) {
        print('✓ EXCELLENT: SigLIP-2 is significantly better (5-10x improvement)');
      } else {
        print('⚠ WARNING: SigLIP-2 improvement is less than expected');
      }

      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Assert expectations
      expect(similarity1, lessThan(0.3), 
        reason: 'SigLIP-1 should have low cross-modal similarity (no projection)');
      expect(similarity2, greaterThan(0.7),
        reason: 'SigLIP-2 should have high cross-modal similarity (with projection)');
      expect(similarity2, greaterThan(similarity1 * 3),
        reason: 'SigLIP-2 should be significantly better than SigLIP-1');

      service1.dispose();
      service2.dispose();
    });
  });

  group('Edge Cases', () {
    late OnnxEmbeddingService service;

    setUp(() async {
      service = OnnxEmbeddingService();
      await service.initialize(
        visionModelPath: siglip1VisionPath,
        textModelPath: siglip1TextPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip1,
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('Handles empty text', () {
      final embedding = service.embedText('');
      expect(embedding.length, 768);
      final norm = _computeL2Norm(embedding);
      expect(norm, closeTo(1.0, 0.01));
      print('✓ Empty text handled correctly');
    });

    test('Handles long text (truncation)', () {
      final longText = 'cat ' * 100; // 400 words
      final embedding = service.embedText(longText);
      expect(embedding.length, 768);
      print('✓ Long text handled correctly (truncated)');
    });

    test('Handles special characters', () {
      final embedding = service.embedText('cat!@#\$%^&*()_+-=[]{}');
      expect(embedding.length, 768);
      print('✓ Special characters handled correctly');
    });

    test('Handles non-English text', () {
      final embedding = service.embedText('猫在桌子上'); // Chinese
      expect(embedding.length, 768);
      print('✓ Non-English text handled correctly');
    });
  });
}
