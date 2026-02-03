/// ONNX Inference Component Tests
///
/// Tests for SiglipInference (ONNX model loading and inference).
/// Run with: flutter test test/component_tests/onnx_inference_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  group('SiglipInference - Constants', () {
    test('image size is 224', () {
      expect(SiglipInference.imageSize, 224);
    });

    test('image channels is 3', () {
      expect(SiglipInference.imageChannels, 3);
    });

    test('max text length is 32', () {
      expect(SiglipInference.maxTextLength, 32);
    });

    test('embedding dimension is 768', () {
      expect(SiglipInference.embeddingDim, 768);
    });
  });

  group('SiglipInference - Initial State', () {
    test('image model not loaded initially', () {
      final inference = SiglipInference();
      expect(inference.isImageModelLoaded, false);
    });

    test('text model not loaded initially', () {
      final inference = SiglipInference();
      expect(inference.isTextModelLoaded, false);
    });
  });

  group('SiglipInference - Error Handling (No Model)', () {
    late SiglipInference inference;

    setUp(() {
      inference = SiglipInference();
    });

    tearDown(() {
      inference.dispose();
    });

    test('embedImage throws StateError when model not loaded', () {
      final testImage = ImagePreprocessor.createTestImage();

      expect(
        () async => await inference.embedImage(testImage),
        throwsA(isA<StateError>()),
      );
    });

    test('embedText throws StateError when model not loaded', () {
      final tokens = List.filled(32, 0);

      expect(
        () async => await inference.embedText(tokens),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SiglipInference - Image Model Loading', () {
    late SiglipInference inference;
    const imageModelPath =
        'assets/model/image_encoder/kitako_image_encoder_int8.onnx';

    setUpAll(() async {
      inference = SiglipInference();
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('loads image model from file', () async {
      final file = File(imageModelPath);
      if (!await file.exists()) {
        print('⚠️ Image model not found at: $imageModelPath');
        markTestSkipped('Image model not found');
        return;
      }

      await inference.loadImageModelFromFile(imageModelPath);
      expect(inference.isImageModelLoaded, true);
      print('✅ Image model loaded successfully');
    });

    test('image model file size is reasonable', () async {
      final file = File(imageModelPath);
      if (!await file.exists()) {
        markTestSkipped('Image model not found');
        return;
      }

      final size = await file.length();
      print('   Image model size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');

      // INT8 quantized model should be reasonable size
      expect(size, greaterThan(1 * 1024 * 1024)); // > 1 MB
      expect(size, lessThan(500 * 1024 * 1024)); // < 500 MB
    });
  });

  group('SiglipInference - Text Model Loading', () {
    late SiglipInference inference;
    const textModelPath =
        'assets/model/text_encoder/kitako_text_encoder_int8.onnx';

    setUpAll(() async {
      inference = SiglipInference();
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('loads text model from file', () async {
      final file = File(textModelPath);
      if (!await file.exists()) {
        print('⚠️ Text model not found at: $textModelPath');
        markTestSkipped('Text model not found');
        return;
      }

      await inference.loadTextModelFromFile(textModelPath);
      expect(inference.isTextModelLoaded, true);
      print('✅ Text model loaded successfully');
    });

    test('text model file size is reasonable', () async {
      final file = File(textModelPath);
      if (!await file.exists()) {
        markTestSkipped('Text model not found');
        return;
      }

      final size = await file.length();
      print('   Text model size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');

      // INT8 quantized model should be reasonable size
      expect(size, greaterThan(1 * 1024 * 1024)); // > 1 MB
      expect(size, lessThan(500 * 1024 * 1024)); // < 500 MB
    });
  });

  group('SiglipInference - Image Embedding', () {
    late SiglipInference inference;
    const imageModelPath =
        'assets/model/image_encoder/kitako_image_encoder_int8.onnx';
    bool modelLoaded = false;

    setUpAll(() async {
      inference = SiglipInference();
      final file = File(imageModelPath);
      if (await file.exists()) {
        try {
          await inference.loadImageModelFromFile(imageModelPath);
          modelLoaded = true;
          print('✅ Image model loaded for inference tests');
        } catch (e) {
          print('❌ Failed to load image model: $e');
        }
      }
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('embedImage returns 768-dimensional vector', () async {
      if (!modelLoaded) {
        markTestSkipped('Image model not loaded');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await inference.embedImage(testImage);

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());

      print('✅ Image embedding generated:');
      print('   Dimension: ${embedding.length}');
      print('   First 5 values: ${embedding.sublist(0, 5)}');
    });

    test('embedImage values are finite', () async {
      if (!modelLoaded) {
        markTestSkipped('Image model not loaded');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await inference.embedImage(testImage);

      for (int i = 0; i < embedding.length; i++) {
        expect(embedding[i].isFinite, true,
            reason: 'Value at index $i should be finite');
        expect(embedding[i].isNaN, false,
            reason: 'Value at index $i should not be NaN');
      }
    });

    test('embedImage rejects invalid input size', () async {
      if (!modelLoaded) {
        markTestSkipped('Image model not loaded');
        return;
      }

      final invalidInput = Float32List(1000); // Wrong size

      expect(
        () async => await inference.embedImage(invalidInput),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('same image produces same embedding', () async {
      if (!modelLoaded) {
        markTestSkipped('Image model not loaded');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final embedding1 = await inference.embedImage(testImage);
      final embedding2 = await inference.embedImage(testImage);

      // Embeddings should be identical for same input
      for (int i = 0; i < embedding1.length; i++) {
        expect(embedding1[i], embedding2[i],
            reason: 'Embedding should be deterministic');
      }

      print('✅ Embeddings are deterministic');
    });
  });

  group('SiglipInference - Text Embedding', () {
    late SiglipInference inference;
    const textModelPath =
        'assets/model/text_encoder/kitako_text_encoder_int8.onnx';
    bool modelLoaded = false;

    setUpAll(() async {
      inference = SiglipInference();
      final file = File(textModelPath);
      if (await file.exists()) {
        try {
          await inference.loadTextModelFromFile(textModelPath);
          modelLoaded = true;
          print('✅ Text model loaded for inference tests');
        } catch (e) {
          print('❌ Failed to load text model: $e');
        }
      }
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('embedText returns 768-dimensional vector', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      // Simple token sequence (padded to 32)
      final tokens = [854, 1, ...List.filled(30, 0)]; // "red" + EOS + padding
      final embedding = await inference.embedText(tokens);

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());

      print('✅ Text embedding generated:');
      print('   Dimension: ${embedding.length}');
      print('   First 5 values: ${embedding.sublist(0, 5)}');
    });

    test('embedText values are finite', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      final tokens = [854, 1, ...List.filled(30, 0)];
      final embedding = await inference.embedText(tokens);

      for (int i = 0; i < embedding.length; i++) {
        expect(embedding[i].isFinite, true,
            reason: 'Value at index $i should be finite');
        expect(embedding[i].isNaN, false,
            reason: 'Value at index $i should not be NaN');
      }
    });

    test('embedText handles short token list (auto-padding)', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      // Provide only a few tokens - should auto-pad to 32
      final shortTokens = [854, 1]; // "red" + EOS
      final embedding = await inference.embedText(shortTokens);

      expect(embedding.length, 768);
      print('✅ Short token list handled correctly');
    });

    test('embedText handles full 32 tokens', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      // Full 32 tokens
      final fullTokens = List.generate(32, (i) => i + 100);
      final embedding = await inference.embedText(fullTokens);

      expect(embedding.length, 768);
      print('✅ Full 32 tokens handled correctly');
    });

    test('same tokens produce same embedding', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      final tokens = [854, 1, ...List.filled(30, 0)];
      final embedding1 = await inference.embedText(tokens);
      final embedding2 = await inference.embedText(tokens);

      for (int i = 0; i < embedding1.length; i++) {
        expect(embedding1[i], embedding2[i],
            reason: 'Embedding should be deterministic');
      }

      print('✅ Text embeddings are deterministic');
    });

    test('different tokens produce different embeddings', () async {
      if (!modelLoaded) {
        markTestSkipped('Text model not loaded');
        return;
      }

      final tokens1 = [854, 1, ...List.filled(30, 0)]; // "red"
      final tokens2 = [8796, 1, ...List.filled(30, 0)]; // "blue"

      final embedding1 = await inference.embedText(tokens1);
      final embedding2 = await inference.embedText(tokens2);

      // Embeddings should be different
      bool anyDifferent = false;
      for (int i = 0; i < embedding1.length; i++) {
        if ((embedding1[i] - embedding2[i]).abs() > 0.001) {
          anyDifferent = true;
          break;
        }
      }

      expect(anyDifferent, true,
          reason: 'Different inputs should produce different embeddings');

      print('✅ Different tokens produce different embeddings');
    });
  });

  group('SiglipInference - Cosine Similarity', () {
    test('identical vectors have similarity 1.0', () {
      final a = Float32List.fromList([1.0, 0.0, 0.0]);
      final b = Float32List.fromList([1.0, 0.0, 0.0]);

      expect(SiglipInference.cosineSimilarity(a, b), closeTo(1.0, 0.001));
    });

    test('orthogonal vectors have similarity 0.0', () {
      final a = Float32List.fromList([1.0, 0.0, 0.0]);
      final b = Float32List.fromList([0.0, 1.0, 0.0]);

      expect(SiglipInference.cosineSimilarity(a, b), closeTo(0.0, 0.001));
    });

    test('opposite vectors have similarity -1.0', () {
      final a = Float32List.fromList([1.0, 0.0, 0.0]);
      final b = Float32List.fromList([-1.0, 0.0, 0.0]);

      expect(SiglipInference.cosineSimilarity(a, b), closeTo(-1.0, 0.001));
    });

    test('throws on mismatched lengths', () {
      final a = Float32List.fromList([1.0, 0.0, 0.0]);
      final b = Float32List.fromList([1.0, 0.0]);

      expect(
        () => SiglipInference.cosineSimilarity(a, b),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles zero vectors', () {
      final a = Float32List.fromList([0.0, 0.0, 0.0]);
      final b = Float32List.fromList([1.0, 0.0, 0.0]);

      // Zero vector should give 0 similarity (no direction)
      expect(SiglipInference.cosineSimilarity(a, b), 0.0);
    });

    test('normalized vectors scale correctly', () {
      // If we double a vector, similarity should remain the same
      final a = Float32List.fromList([1.0, 2.0, 3.0]);
      final b = Float32List.fromList([2.0, 4.0, 6.0]); // a * 2
      final c = Float32List.fromList([1.0, 2.0, 3.0]); // same as a

      final sim1 = SiglipInference.cosineSimilarity(a, b);
      final sim2 = SiglipInference.cosineSimilarity(a, c);

      expect(sim1, closeTo(1.0, 0.001),
          reason: 'Parallel vectors should have similarity 1');
      expect(sim2, closeTo(1.0, 0.001));
    });
  });

  group('SiglipInference - Resource Cleanup', () {
    test('dispose releases resources', () {
      final inference = SiglipInference();
      inference.dispose();

      expect(inference.isImageModelLoaded, false);
      expect(inference.isTextModelLoaded, false);
    });

    test('can dispose without loading models', () {
      final inference = SiglipInference();
      expect(() => inference.dispose(), returnsNormally);
    });
  });
}
